import XCTest
@testable import Nowdeck

/// Experimental playlist folders: the tree, the rootlist protobuf and the library flow.
@MainActor
final class PlaylistFoldersTests: XCTestCase {
    // MARK: Tree

    func testTreeNestsFoldersInSpotifyOrder() {
        let tree = PlaylistTree.build(from: [
            "spotify:playlist:top",
            "spotify:start-group:f1:Para+laburar",
            "spotify:playlist:a",
            "spotify:start-group:f2:Lo%20fi",
            "spotify:playlist:b",
            "spotify:end-group:f2",
            "spotify:end-group:f1",
            "spotify:playlist:last",
        ])

        let inner = PlaylistFolder(id: "f2", name: "Lo fi", children: [.playlist(uri: "spotify:playlist:b")])
        let outer = PlaylistFolder(id: "f1", name: "Para laburar",
                                   children: [.playlist(uri: "spotify:playlist:a"), .folder(inner)])
        XCTAssertEqual(tree, [.playlist(uri: "spotify:playlist:top"), .folder(outer),
                              .playlist(uri: "spotify:playlist:last")])
        XCTAssertEqual(outer.playlistCount, 2)
    }

    func testTreeToleratesBrokenMarkersAndOtherRows() {
        let tree = PlaylistTree.build(from: [
            "spotify:end-group:orphan",
            "spotify:album:not-a-playlist",
            "spotify:start-group:f1:Abierta",
            "spotify:playlist:a",
        ])
        XCTAssertEqual(tree, [.folder(PlaylistFolder(id: "f1", name: "Abierta",
                                                     children: [.playlist(uri: "spotify:playlist:a")]))])
    }

    func testFolderNamesAreDecoded() {
        XCTAssertEqual(PlaylistTree.decodeFolderName("Late%20Night+Mix"), "Late Night Mix")
        XCTAssertEqual(PlaylistTree.decodeFolderName("Canci%C3%B3n"), "Canción")
        XCTAssertEqual(PlaylistTree.decodeFolderName("100%+puro"), "100% puro",
                       "A broken escape keeps the text")
    }

    func testChildrenAtAPath() {
        let tree = PlaylistTree.build(from: [
            "spotify:start-group:f1:A", "spotify:start-group:f2:B", "spotify:playlist:x",
            "spotify:end-group:f2", "spotify:end-group:f1",
        ])
        XCTAssertEqual(PlaylistTree.children(of: tree, at: ["f1", "f2"]),
                       [.playlist(uri: "spotify:playlist:x")])
        XCTAssertNil(PlaylistTree.children(of: tree, at: ["missing"]))
    }

    // MARK: Protobuf

    func testRootlistPageIsDecoded() throws {
        let data = Proto.rootlist(length: 3, truncated: true, rows: [
            ("spotify:start-group:f1:Mixes", nil, nil),
            ("spotify:playlist:a", "Asado", 42),
            ("spotify:end-group:f1", nil, nil),
        ])

        let page = try RootlistPage.decode(data)

        XCTAssertEqual(page.totalLength, 3)
        XCTAssertTrue(page.isTruncated)
        XCTAssertEqual(page.rows, [
            RootlistRow(uri: "spotify:start-group:f1:Mixes", name: nil, length: nil),
            RootlistRow(uri: "spotify:playlist:a", name: "Asado", length: 42),
            RootlistRow(uri: "spotify:end-group:f1", name: nil, length: nil),
        ])
    }

    func testTruncatedProtobufIsAnError() {
        var data = Proto.rootlist(length: 1, truncated: false,
                                  rows: [("spotify:playlist:a", nil, nil)])
        data.removeLast(3)
        XCTAssertThrowsError(try RootlistPage.decode(data))
    }

    func testHugeFieldLengthIsAnErrorInsteadOfACrash() {
        // A length-delimited field claiming `UInt64.max` bytes, in a field that is read and
        // in one that is skipped.
        for field in [5, 9] {
            let data = Data(Proto.key(field, 2) + Proto.varint(.max))
            XCTAssertThrowsError(try RootlistPage.decode(data)) { error in
                guard case .truncated = error as? ProtobufReader.Failure else {
                    return XCTFail("Expected truncated, got \(error)")
                }
            }
        }
    }

    // MARK: Library

    private func makeModel(rootlistStatus: StubBox<Int> = StubBox(200)) -> (LibraryModel, StubRecorder) {
        let playlists = LibraryJSON.page([LibraryJSON.playlist("Asado", id: "a"),
                                          LibraryJSON.playlist("Suelta", id: "s")])
        let rootlist = Proto.rootlist(length: 4, truncated: false, rows: [
            ("spotify:start-group:f1:Fin+de+semana", nil, nil),
            ("spotify:playlist:a", nil, nil),
            ("spotify:playlist:spotifys", "Hecha por Spotify", 30),
            ("spotify:end-group:f1", nil, nil),
            ("spotify:playlist:s", nil, nil),
        ])
        let (api, recorder) = makeLibraryTestAPI { request in
            let url = request.url!
            switch (url.host ?? "", url.path) {
            case ("api.spotify.com", "/v1/me"):
                return (.stub(200), Data(#"{"id":"lauti"}"#.utf8))
            case ("api.spotify.com", "/v1/me/playlists"):
                return (.stub(200), playlists)
            case ("spclient.wg.spotify.com", "/playlist/v2/user/lauti/rootlist"):
                let status = rootlistStatus.value
                return (.stub(status), status == 200 ? rootlist : Data())
            default:
                return (.stub(204), Data())
            }
        }
        return (LibraryModel(api: api, folders: PlaylistFolderClient(api: api)), recorder)
    }

    func testPlaylistsRowShowsFoldersAndOpensThem() async throws {
        let (model, recorder) = makeModel()

        await model.load(.playlists)

        XCTAssertTrue(model.showsFolders)
        guard case .loaded(let top) = model.state(of: .playlists) else {
            return XCTFail("Expected the top level")
        }
        XCTAssertEqual(top.map(\.name), ["Fin de semana", "Suelta"])
        XCTAssertEqual(top.first?.kind, .folder(id: "f1"))

        let outcome = await model.play(top[0])
        XCTAssertEqual(outcome, .openedFolder)
        XCTAssertEqual(model.folderPath.map(\.name), ["Fin de semana"])
        guard case .loaded(let inside) = model.state(of: .playlists) else {
            return XCTFail("Expected the folder's contents")
        }
        XCTAssertEqual(inside.map(\.name), ["Asado", "Hecha por Spotify"],
                       "A playlist only the rootlist knows keeps its rootlist name")

        model.closeFolder()
        XCTAssertTrue(model.folderPath.isEmpty)

        let rootlistRequest = try XCTUnwrap(recorder.requests.first { $0.url?.host == "spclient.wg.spotify.com" })
        XCTAssertEqual(rootlistRequest.queryValues["from"], "0")
        XCTAssertNotNil(rootlistRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(rootlistRequest.value(forHTTPHeaderField: "client-token"),
                     "Nowdeck never imitates Spotify's own client")
    }

    func testPlaylistDetailReturnsToTheOpenFolder() async throws {
        let (model, _) = makeModel()
        await model.load(.playlists)
        model.openFolder(id: "f1")
        guard case .loaded(let inside) = model.state(of: .playlists) else {
            return XCTFail("Expected the folder's contents")
        }
        let playlist = try XCTUnwrap(inside.first { $0.uri == "spotify:playlist:spotifys" })

        model.showDetail(of: playlist)
        XCTAssertEqual(model.detail?.entry, playlist)
        XCTAssertEqual(model.detail?.entry.detailSubtitle, "30 temas")

        model.closeDetail()
        XCTAssertNil(model.detail)
        XCTAssertEqual(model.folderPath.map(\.id), ["f1"])
        XCTAssertEqual(model.state(of: .playlists), .loaded(inside))
    }

    func testRejectedRootlistFallsBackToTheFlatListWithANotice() async {
        let (model, _) = makeModel(rootlistStatus: StubBox(401))

        await model.load(.playlists)

        XCTAssertFalse(model.showsFolders)
        XCTAssertEqual(model.notice, .foldersUnavailable)
        guard case .loaded(let items) = model.state(of: .playlists) else {
            return XCTFail("Expected the flat list")
        }
        XCTAssertEqual(items.map(\.name), ["Asado", "Suelta"])
    }

    func testFailedReloadClosesTheOpenFolder() async {
        let status = StubBox(200)
        let (model, _) = makeModel(rootlistStatus: status)
        await model.load(.playlists)
        model.openFolder(id: "f1")
        XCTAssertEqual(model.folderPath.map(\.name), ["Fin de semana"])

        status.value = 401
        await model.load(.playlists)

        XCTAssertFalse(model.showsFolders)
        XCTAssertTrue(model.folderPath.isEmpty, "The flat list shows no folder back bar")
        guard case .loaded(let items) = model.state(of: .playlists) else {
            return XCTFail("Expected the flat list")
        }
        XCTAssertEqual(items.map(\.name), ["Asado", "Suelta"])
    }
}

/// Builds rootlist answers with the field numbers `RootlistPage.decode` reads.
private enum Proto {
    static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    static func key(_ field: Int, _ wireType: Int) -> [UInt8] {
        varint(UInt64(field << 3 | wireType))
    }

    static func bytes(_ field: Int, _ payload: [UInt8]) -> [UInt8] {
        key(field, 2) + varint(UInt64(payload.count)) + payload
    }

    static func number(_ field: Int, _ value: Int) -> [UInt8] {
        key(field, 0) + varint(UInt64(value))
    }

    static func rootlist(length: Int, truncated: Bool,
                         rows: [(uri: String, name: String?, length: Int?)]) -> Data {
        var contents = number(1, 0) + number(2, truncated ? 1 : 0)
        for row in rows {
            // An attributes field Nowdeck does not read, to check it is skipped.
            let item = bytes(1, Array(row.uri.utf8)) + bytes(2, number(2, 1_700_000_000))
            contents += bytes(3, item)
        }
        for row in rows {
            var meta: [UInt8] = []
            if let name = row.name { meta += bytes(2, bytes(1, Array(name.utf8)) + number(4, 0)) }
            if let length = row.length { meta += number(3, length) }
            contents += bytes(4, meta)
        }
        let message = bytes(1, [0xAB, 0xCD]) + number(2, length) + bytes(5, contents)
        return Data(message)
    }
}
