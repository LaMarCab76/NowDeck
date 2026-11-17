import XCTest
@testable import Nowdeck

/// `LibraryModel`: pagination of a row, filters and playing a card.
@MainActor
final class LibraryModelTests: XCTestCase {
    // MARK: Pagination

    nonisolated private static func items(_ range: Range<Int>) -> [LibraryEntry] {
        range.map { LibraryEntry(kind: .playlist, uri: "spotify:playlist:p\($0)", name: "P\($0)",
                                subtitle: "Playlist", artworkURL: nil, pageURL: nil) }
    }

    func testRowFetchesNextPageUntilItHasTwentyItems() async throws {
        let offsets = OffsetRecorder()
        let row = try await LibraryModel.collectRow { offset in
            offsets.record(offset)
            // First page: 20 positions but only 15 usable items (nulls dropped).
            return offset == 0 ? (Self.items(0..<15), 20) : (Self.items(20..<30), 40)
        }

        XCTAssertEqual(offsets.values, [0, 20])
        XCTAssertEqual(row.count, 20)
        XCTAssertEqual(row.last?.uri, "spotify:playlist:p24")
    }

    func testRowStopsOnLastPage() async throws {
        let offsets = OffsetRecorder()
        let row = try await LibraryModel.collectRow { offset in
            offsets.record(offset)
            return (Self.items(0..<3), nil)
        }
        XCTAssertEqual(offsets.values, [0])
        XCTAssertEqual(row.count, 3)
    }

    func testRowReadsAtMostThreePagesAndDropsDuplicates() async throws {
        let offsets = OffsetRecorder()
        let row = try await LibraryModel.collectRow { offset in
            offsets.record(offset)
            return (Self.items(0..<2), offset + 20)
        }
        XCTAssertEqual(offsets.values, [0, 20, 40])
        XCTAssertEqual(row.map(\.uri), ["spotify:playlist:p0", "spotify:playlist:p1"])
    }

    // MARK: Filters

    /// Routes each library path to a body; anything else answers 204.
    private func makeModel(_ routes: [String: (Int, Data)]) -> (LibraryModel, StubRecorder) {
        let (api, recorder) = makeLibraryTestAPI { request in
            let path = request.url?.path ?? ""
            if let (status, body) = routes[path] { return (.stub(status), body) }
            return (.stub(204), Data())
        }
        return (LibraryModel(api: api), recorder)
    }

    private let playlists = LibraryJSON.page([LibraryJSON.playlist("Para laburar", id: "p1"),
                                              LibraryJSON.playlist("Asado del domingo", id: "p2")])

    func testOpenLoadsPlaylistsAndHidesAudiobooksWhenEmpty() async {
        let (model, recorder) = makeModel([
            "/v1/me/playlists": (200, playlists),
            "/v1/me/audiobooks": (200, LibraryJSON.page([])),
        ])

        await model.open()

        XCTAssertEqual(model.filter, .playlists)
        XCTAssertEqual(model.filters, [.playlists, .albums, .shows])
        guard case .loaded(let cards) = model.state(of: .playlists) else {
            return XCTFail("Playlists not loaded")
        }
        XCTAssertEqual(cards.map(\.name), ["Para laburar", "Asado del domingo"])
        XCTAssertEqual(Set(recorder.requests.compactMap { $0.url?.path }),
                       ["/v1/me/playlists", "/v1/me/audiobooks"],
                       "Albums and podcasts load only when their filter is chosen")
    }

    func testAudiobooksFilterAppearsWhenThereAreAudiobooks() async {
        let (model, _) = makeModel([
            "/v1/me/playlists": (200, playlists),
            "/v1/me/audiobooks": (200, LibraryJSON.page([LibraryJSON.audiobook("El faro", id: "b1")])),
        ])

        await model.open()

        XCTAssertEqual(model.filters, LibraryFilter.allCases)
    }

    func testAudiobooksFilterStaysHiddenWhenTheRequestFails() async {
        let (model, _) = makeModel([
            "/v1/me/playlists": (200, playlists),
            "/v1/me/audiobooks": (403, spotifyErrorJSON(status: 403, message: "Forbidden")),
        ])

        await model.open()

        XCTAssertEqual(model.filters, [.playlists, .albums, .shows])
    }

    func testSelectingAFilterLoadsItOnce() async {
        let (model, recorder) = makeModel([
            "/v1/me/albums": (200, LibraryJSON.page([LibraryJSON.savedAlbum("Costanera", id: "a1",
                                                                             artist: "Marea Baja")])),
        ])

        await model.select(.albums)
        await model.select(.playlists)
        await model.select(.albums)

        XCTAssertEqual(model.filter, .albums)
        guard case .loaded(let cards) = model.state(of: .albums) else {
            return XCTFail("Albums not loaded")
        }
        XCTAssertEqual(cards.first?.subtitle, "Álbum · Marea Baja")
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/v1/me/albums" }.count, 1)
    }

    func testLoadErrorsBecomeRowStates() async {
        let (model, _) = makeModel([
            "/v1/me/playlists": (403, spotifyErrorJSON(status: 403, message: "Forbidden")),
            "/v1/me/albums": (500, Data()),
            "/v1/me/shows": (429, spotifyErrorJSON(status: 429, message: "Slow down")),
        ])

        await model.load(.playlists)
        await model.load(.albums)
        await model.load(.shows)

        XCTAssertEqual(model.state(of: .playlists), .failed(.forbidden))
        XCTAssertEqual(model.state(of: .albums), .failed(.failed))
        XCTAssertEqual(model.state(of: .shows), .failed(.rateLimited))
    }

    func testRetryLoadsTheSelectedRowAgain() async {
        let attempts = OffsetRecorder()
        let (api, _) = makeLibraryTestAPI { _ in
            attempts.record(0)
            if attempts.values.count == 1 { return (.stub(403), Data()) }
            return (.stub(200), LibraryJSON.page([LibraryJSON.playlist("Ruta 2", id: "p3")]))
        }
        let model = LibraryModel(api: api)

        await model.load(.playlists)
        XCTAssertEqual(model.state(of: .playlists), .failed(.forbidden))
        await model.retry()

        guard case .loaded(let cards) = model.state(of: .playlists) else {
            return XCTFail("Not loaded after retry")
        }
        XCTAssertEqual(cards.map(\.name), ["Ruta 2"])
    }

    // MARK: Playing a card

    private let album = LibraryEntry(kind: .album, uri: "spotify:album:a1", name: "Costanera",
                                    subtitle: "Álbum · Marea Baja", artworkURL: nil,
                                    pageURL: URL(string: "https://open.spotify.com/album/a1"))

    func testPlayingAnAlbumStartsItsContext() async throws {
        let (model, recorder) = makeModel(["/v1/me/player/play": (204, Data())])

        let outcome = await model.play(album)

        XCTAssertEqual(outcome, .started)
        XCTAssertNil(model.notice)
        XCTAssertNil(model.startingURI)
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String],
                       ["context_uri": "spotify:album:a1"])
    }

    func testNoActiveDeviceAsksForDevices() async {
        let (model, _) = makeModel([
            "/v1/me/player/play": (404, spotifyErrorJSON(status: 404, message: "No active device")),
        ])

        let outcome = await model.play(album)

        XCTAssertEqual(outcome, .noActiveDevice)
        XCTAssertEqual(model.notice, .noActiveDevice)
    }

    func testForbiddenShowsAGenericNotice() async {
        let (model, _) = makeModel([
            "/v1/me/player/play": (403, spotifyErrorJSON(status: 403, message: "Premium required")),
        ])

        let outcome = await model.play(album)

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(model.notice, .forbidden)
    }

    func testPodcastsOpenInSpotifyWithoutCallingTheAPI() async {
        let (model, recorder) = makeModel([:])
        let show = LibraryEntry(kind: .show, uri: "spotify:show:s1", name: "Charla",
                               subtitle: "Podcast", artworkURL: nil,
                               pageURL: URL(string: "https://open.spotify.com/show/s1"))

        let outcome = await model.play(show)

        XCTAssertEqual(outcome, .openInSpotify(URL(string: "https://open.spotify.com/show/s1")))
        XCTAssertTrue(recorder.requests.isEmpty)
    }
}
