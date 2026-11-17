import Foundation

// Experimental playlist folders (owner's decision, 2026-11-17).
//
// Spotify's Web API does not return playlist folders ("Folders are not returned through the
// Web API", developer.spotify.com, Playlists concept). Spotify's own apps read them from the
// account's **rootlist**, an undocumented endpoint of its internal playlist service:
//
//     GET https://spclient.wg.spotify.com/playlist/v2/user/{user id}/rootlist
//         ?decorate=revision,attributes,length&from=0&length=500
//
// The answer is a protobuf `SelectedListContent` (field numbers from librespot's
// `playlist4_external.proto`, MIT). Folders are brackets inside the flat list of URIs:
//
//     spotify:start-group:<id>:<percent-encoded name, + for spaces>
//     spotify:playlist:…
//     spotify:end-group:<id>
//
// Limits, all explained to the user before turning this on:
// - Not approved by Spotify for third-party apps; it may stop working or get the app's
//   Client ID blocked.
// - Nowdeck sends only the user's own Web API token. It does **not** imitate Spotify's
//   client (no `client-token`, no web-player token). If the service rejects the token, the
//   library falls back to the flat list and says so.

/// A folder of the user's playlist tree.
struct PlaylistFolder: Equatable, Sendable {
    var id: String
    var name: String
    var children: [PlaylistTreeNode]

    /// Playlists inside, counting sub-folders.
    var playlistCount: Int {
        children.reduce(0) { count, node in
            switch node {
            case .playlist: return count + 1
            case .folder(let folder): return count + folder.playlistCount
            }
        }
    }
}

indirect enum PlaylistTreeNode: Equatable, Sendable {
    case playlist(uri: String)
    case folder(PlaylistFolder)
}

/// What the rootlist says about one row, besides its URI.
struct RootlistRow: Equatable, Sendable {
    var uri: String
    /// From the row's metadata; used only for playlists the Web API did not return.
    var name: String?
    var length: Int?
}

// MARK: - Tree

enum PlaylistTree {
    /// Builds the tree from the rootlist rows, in Spotify's order. Rows that are neither a
    /// playlist nor a folder marker are dropped; an `end-group` without its start is ignored,
    /// and folders Spotify never closed are closed at the end.
    static func build(from uris: [String]) -> [PlaylistTreeNode] {
        // A stack of open folders; the bottom one is the root.
        var stack: [PlaylistFolder] = [PlaylistFolder(id: "", name: "", children: [])]
        for uri in uris {
            if let rest = uri.dropPrefix("spotify:start-group:") {
                let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                let id = String(parts[0])
                let name = parts.count > 1 ? decodeFolderName(String(parts[1])) : ""
                stack.append(PlaylistFolder(id: id, name: name, children: []))
            } else if uri.hasPrefix("spotify:end-group:") {
                guard stack.count > 1 else { continue }
                let closed = stack.removeLast()
                stack[stack.count - 1].children.append(.folder(closed))
            } else if uri.hasPrefix("spotify:playlist:"), SpotifyURI(uri) != nil {
                stack[stack.count - 1].children.append(.playlist(uri: uri))
            }
        }
        while stack.count > 1 {
            let closed = stack.removeLast()
            stack[stack.count - 1].children.append(.folder(closed))
        }
        return stack[0].children
    }

    /// Folder names arrive percent-encoded, with `+` for a space. A malformed escape keeps
    /// the text as it came.
    static func decodeFolderName(_ encoded: String) -> String {
        let spaced = encoded.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    /// The children of the folder at `path` (folder ids from the root), or `nil` if the
    /// path no longer exists.
    static func children(of tree: [PlaylistTreeNode], at path: [String]) -> [PlaylistTreeNode]? {
        var level = tree
        for id in path {
            let folder = level.lazy.compactMap { node -> PlaylistFolder? in
                if case .folder(let folder) = node, folder.id == id { return folder }
                return nil
            }.first
            guard let folder else { return nil }
            level = folder.children
        }
        return level
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

// MARK: - Protobuf

/// Just enough of the protobuf wire format to read a rootlist page: varints and
/// length-delimited fields; everything else is skipped.
struct ProtobufReader {
    enum Failure: Error {
        case truncated
        case unsupportedWireType(Int)
    }

    private let bytes: [UInt8]
    private var index: Int

    init(_ data: Data) {
        bytes = [UInt8](data)
        index = 0
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
        index = 0
    }

    var isAtEnd: Bool { index >= bytes.count }

    /// The next field's number and wire type, or `nil` at the end.
    mutating func nextField() throws -> (number: Int, wireType: Int)? {
        guard !isAtEnd else { return nil }
        let key = try readVarint()
        return (Int(key >> 3), Int(key & 0x7))
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < bytes.count, shift < 64 else { throw Failure.truncated }
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
    }

    mutating func readBytes() throws -> [UInt8] {
        let length = Int(try readVarint())
        guard length >= 0, index + length <= bytes.count else { throw Failure.truncated }
        defer { index += length }
        return Array(bytes[index..<index + length])
    }

    mutating func readMessage() throws -> ProtobufReader {
        ProtobufReader(bytes: try readBytes())
    }

    mutating func readString() throws -> String {
        String(decoding: try readBytes(), as: UTF8.self)
    }

    mutating func skip(wireType: Int) throws {
        switch wireType {
        case 0: _ = try readVarint()
        case 1: try advance(8)
        case 2: _ = try readBytes()
        case 5: try advance(4)
        default: throw Failure.unsupportedWireType(wireType)
        }
    }

    private mutating func advance(_ count: Int) throws {
        guard index + count <= bytes.count else { throw Failure.truncated }
        index += count
    }
}

/// One page of the rootlist.
struct RootlistPage: Equatable, Sendable {
    var rows: [RootlistRow]
    /// More rows follow this page.
    var isTruncated: Bool
    /// The list's total length, when Spotify sends it.
    var totalLength: Int?

    /// Reads a `SelectedListContent`:
    /// `length = 2`, `contents = 5` (`ListItems`: `truncated = 2`, `items = 3`,
    /// `meta_items = 4`); `Item.uri = 1`; `MetaItem.attributes = 2`, `MetaItem.length = 3`;
    /// `ListAttributes.name = 1`. Meta items line up with items by position.
    static func decode(_ data: Data) throws -> RootlistPage {
        var reader = ProtobufReader(data)
        var totalLength: Int?
        var uris: [String] = []
        var metas: [(name: String?, length: Int?)] = []
        var truncated = false

        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (2, 0):
                totalLength = Int(truncatingIfNeeded: try reader.readVarint())
            case (5, 2):
                var contents = try reader.readMessage()
                while let inner = try contents.nextField() {
                    switch (inner.number, inner.wireType) {
                    case (2, 0):
                        truncated = try contents.readVarint() != 0
                    case (3, 2):
                        var item = try contents.readMessage()
                        var uri = ""
                        while let itemField = try item.nextField() {
                            if itemField == (1, 2) {
                                uri = try item.readString()
                            } else {
                                try item.skip(wireType: itemField.wireType)
                            }
                        }
                        uris.append(uri)
                    case (4, 2):
                        var meta = try contents.readMessage()
                        metas.append(try decodeMeta(&meta))
                    default:
                        try contents.skip(wireType: inner.wireType)
                    }
                }
            default:
                try reader.skip(wireType: field.wireType)
            }
        }

        let rows = uris.enumerated().map { index, uri in
            let meta = index < metas.count ? metas[index] : (name: nil, length: nil)
            return RootlistRow(uri: uri, name: meta.name, length: meta.length)
        }
        return RootlistPage(rows: rows, isTruncated: truncated, totalLength: totalLength)
    }

    private static func decodeMeta(_ meta: inout ProtobufReader) throws -> (name: String?, length: Int?) {
        var name: String?
        var length: Int?
        while let field = try meta.nextField() {
            switch (field.number, field.wireType) {
            case (2, 2):
                var attributes = try meta.readMessage()
                while let attribute = try attributes.nextField() {
                    if attribute == (1, 2) {
                        name = try attributes.readString()
                    } else {
                        try attributes.skip(wireType: attribute.wireType)
                    }
                }
            case (3, 0):
                length = Int(truncatingIfNeeded: try meta.readVarint())
            default:
                try meta.skip(wireType: field.wireType)
            }
        }
        return (name, length)
    }
}

// MARK: - Client

/// Reads the rootlist with the user's Web API token.
struct PlaylistFolderClient: Sendable {
    enum Failure: Error, Equatable {
        /// The service did not accept the request (any non-2xx answer, typically 401/403).
        case rejected(status: Int)
        case unreadable
    }

    static let baseURL = URL(string: "https://spclient.wg.spotify.com")!
    static let pageLength = 500
    /// 10 pages of 500 rows: far more than any real library, and a hard stop if the
    /// service keeps saying "truncated".
    static let maxPages = 10

    let api: SpotifyAPI
    var baseURL: URL = PlaylistFolderClient.baseURL

    /// The account's rows in Spotify's order, every page.
    func rootlist() async throws -> [RootlistRow] {
        let userID = try await api.currentUserID()
        var rows: [RootlistRow] = []
        for _ in 0..<Self.maxPages {
            let page = try await fetchPage(userID: userID, from: rows.count)
            rows += page.rows
            guard page.isTruncated, !page.rows.isEmpty else { break }
        }
        return rows
    }

    private func fetchPage(userID: String, from: Int) async throws -> RootlistPage {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/playlist/v2/user/\(SpotifyAPI.pathComponent(userID))/rootlist"
        components.queryItems = [
            URLQueryItem(name: "decorate", value: "revision,attributes,length"),
            URLQueryItem(name: "from", value: String(from)),
            URLQueryItem(name: "length", value: String(Self.pageLength)),
        ]
        let (data, status) = try await api.getOutsideWebAPI(components.url!)
        guard (200..<300).contains(status) else { throw Failure.rejected(status: status) }
        do {
            return try RootlistPage.decode(data)
        } catch {
            throw Failure.unreadable
        }
    }
}
