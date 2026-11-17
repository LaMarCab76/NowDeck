import Foundation

/// Disk cache of LRCLIB answers, keyed by Spotify `item.id` (docs/04-letras.md).
///
/// - Found records are kept for 30 days; "no lyrics" answers (`404`) for 7 days, so tracks
///   without lyrics are not asked again on every play.
/// - The raw record is stored, not the parsed stanzas, so parser fixes apply to cached
///   entries too.
/// - Lives in `Library/Caches`: iOS may purge it, which only costs a new request.
/// - Errors (network, rate limit, 5xx) are never cached.
actor LyricsCache {
    struct Entry: Codable, Equatable {
        var savedAt: Date
        /// `nil` = LRCLIB answered `404`.
        var record: LRCLIBRecord?
    }

    static let foundLifetime: TimeInterval = 30 * 24 * 60 * 60
    static let notFoundLifetime: TimeInterval = 7 * 24 * 60 * 60
    /// Oldest entries beyond this count are removed when saving.
    static let maxEntries = 500

    private let directory: URL
    private let now: @Sendable () -> Date
    private let fileManager = FileManager.default

    init(directory: URL = LyricsCache.defaultDirectory, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyrics", isDirectory: true)
    }

    enum Lookup: Equatable {
        /// Nothing cached, or it expired.
        case miss
        /// LRCLIB had no lyrics for this track.
        case notFound
        case found(LRCLIBRecord)
    }

    /// The cached answer for the track, if it has not expired.
    func lookup(spotifyID id: String) -> Lookup {
        guard let url = fileURL(forSpotifyID: id),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return .miss }

        let lifetime = entry.record == nil ? Self.notFoundLifetime : Self.foundLifetime
        guard now().timeIntervalSince(entry.savedAt) < lifetime else {
            try? fileManager.removeItem(at: url)
            return .miss
        }
        if let record = entry.record { return .found(record) }
        return .notFound
    }

    /// Saves an answer; `record == nil` stores a "no lyrics" answer.
    func store(_ record: LRCLIBRecord?, forSpotifyID id: String) {
        guard let url = fileURL(forSpotifyID: id) else { return }
        let entry = Entry(savedAt: now(), record: record)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: url, options: .atomic)
        } catch {
            return
        }
        pruneIfNeeded()
    }

    func removeAll() {
        try? fileManager.removeItem(at: directory)
    }

    /// Spotify IDs are base-62. Anything else (empty, or with `/` or `..`) is not used as a
    /// file name, so a strange ID can never point outside the cache folder.
    private func fileURL(forSpotifyID id: String) -> URL? {
        guard (1...64).contains(id.count), id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        return directory.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func pruneIfNeeded() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ), files.count > Self.maxEntries else { return }

        let byAge = files.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return left < right
        }
        for file in byAge.prefix(files.count - Self.maxEntries) {
            try? fileManager.removeItem(at: file)
        }
    }
}
