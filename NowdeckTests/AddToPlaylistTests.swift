import XCTest
@testable import Nowdeck

/// Agregar a una playlist: the request, the editable playlists, the sheet's model, the item
/// that can be added and the controls row that makes room for the button.
@MainActor
final class AddToPlaylistTests: XCTestCase {
    private let trackURI = "spotify:track:6rqhFgbbKwnb9MLmUQDhG6"

    private func makeAPI(handler: @escaping StubURLProtocol.Handler) -> (SpotifyAPI, StubRecorder) {
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let clock = TestClock()
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, now: { clock.now },
                             sleep: { _ in }, jitter: { 0 })
        return (api, recorder)
    }

    nonisolated private static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    nonisolated private static func playlist(_ id: String, owner: String,
                                             collaborative: Bool = false,
                                             count: Int = 3) -> [String: Any] {
        ["id": id, "name": "Lista \(id)", "uri": "spotify:playlist:\(id)",
         "collaborative": collaborative, "owner": ["id": owner],
         "items": ["total": count], "images": []]
    }

    /// `GET /me` answers `me`; `GET /me/playlists` answers one page with `playlists`;
    /// `POST …/items` answers `addStatus`.
    nonisolated private static func routes(
        playlists: [[String: Any]],
        addStatus: Int = 201
    ) -> StubURLProtocol.Handler {
        let page = json(["items": playlists, "limit": 50, "offset": 0,
                         "total": playlists.count, "next": NSNull()])
        return { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod ?? "GET", path) {
            case ("GET", "/v1/me"):
                return (.stub(200), json(["id": "me"]))
            case ("GET", "/v1/me/playlists"):
                return (.stub(200), page)
            case ("POST", _):
                if addStatus == 201 { return (.stub(201), json(["snapshot_id": "snap"])) }
                return (.stub(addStatus), spotifyErrorJSON(status: addStatus, message: "No"))
            default:
                return (.stub(404), Data())
            }
        }
    }

    // MARK: Request

    func testAddSendsTheURIToTheItemsEndpoint() async throws {
        let (api, recorder) = makeAPI { _ in (.stub(201), Self.json(["snapshot_id": "abc"])) }

        let snapshot = try await api.addToPlaylist(playlistID: "pl1", uri: trackURI)

        XCTAssertEqual(snapshot, "abc")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.spotify.com/v1/playlists/pl1/items")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"uris":["\#(trackURI)"]}"#)
    }

    func testAddIsNotRetriedAfterAServerError() async {
        let (api, recorder) = makeAPI { _ in (.stub(503), Data()) }

        do {
            try await api.addToPlaylist(playlistID: "pl1", uri: trackURI)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(AddToPlaylistProblem(error, whileAdding: true), .connection)
        }
        XCTAssertEqual(recorder.requests.count, 1, "A retry could add the track twice")
    }

    func testAllPlaylistsFollowsThePages() async throws {
        let (api, recorder) = makeAPI { request in
            let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "offset" }?.value
            if offset == "0" {
                return (.stub(200), Self.json([
                    "items": [Self.playlist("a", owner: "me")], "limit": 50, "offset": 0,
                    "next": "https://api.spotify.com/v1/me/playlists?offset=50"]))
            }
            return (.stub(200), Self.json([
                "items": [Self.playlist("b", owner: "me")], "limit": 50, "offset": 50,
                "next": NSNull()]))
        }

        let playlists = try await api.allSavedPlaylists()

        XCTAssertEqual(playlists.map(\.id), ["a", "b"])
        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertTrue(recorder.requests[0].url!.absoluteString.contains("limit=50"))
    }

    func testAllPlaylistsStopsAfterTheMaximumPages() async throws {
        let (api, recorder) = makeAPI { _ in
            (.stub(200), Self.json(["items": [], "limit": 50, "offset": 0,
                                    "next": "https://api.spotify.com/v1/me/playlists"]))
        }

        _ = try await api.allSavedPlaylists(maximumPages: 3)

        XCTAssertEqual(recorder.requests.count, 3)
    }

    // MARK: Editable playlists

    func testOnlyOwnedAndCollaborativePlaylistsAreEditable() throws {
        let data = Self.json([
            Self.playlist("mine", owner: "me"),
            Self.playlist("followed", owner: "other"),
            Self.playlist("shared", owner: "other", collaborative: true),
            Self.playlist("mine", owner: "me"),
            ["id": "noname", "name": "", "owner": ["id": "me"]],
        ])
        let playlists = try SpotifyAPI.makeDecoder().decode([SimplifiedPlaylist].self, from: data)

        let editable = EditablePlaylist.editable(from: playlists, userID: "me")

        XCTAssertEqual(editable.map(\.id), ["mine", "shared"])
        XCTAssertFalse(editable[0].isCollaborative)
        XCTAssertTrue(editable[1].isCollaborative)
        XCTAssertEqual(editable[0].itemCount, 3)
    }

    func testOwnCollaborativePlaylistIsNotLabeledCollaborative() {
        let playlist = SimplifiedPlaylist(id: "p", name: "P", owner: .init(id: "me"),
                                          collaborative: true)
        XCTAssertEqual(EditablePlaylist.editable(from: [playlist], userID: "me").first?
            .isCollaborative, false)
    }

    // MARK: Item that can be added

    func testTracksAndEpisodesCanBeAddedButNotLocalFilesOrAds() {
        let track = NowPlaying(item: .track(SpotifyTrack(name: "T", uri: trackURI,
                                                         durationMs: 1)))
        XCTAssertEqual(track?.playlistURI, trackURI)

        let local = NowPlaying(item: .track(SpotifyTrack(name: "L", uri: "spotify:local:a:b:c:1",
                                                         durationMs: 1, isLocal: true)))
        XCTAssertNil(local?.playlistURI)

        let episode = NowPlaying(item: .episode(SpotifyEpisode(
            name: "E", uri: "spotify:episode:512ojhOuo1ktJprKbVcKyQ", durationMs: 1)))
        XCTAssertEqual(episode?.playlistURI, "spotify:episode:512ojhOuo1ktJprKbVcKyQ")

        let wrongKind = NowPlaying(item: .track(SpotifyTrack(name: "W", uri: "spotify:album:x1",
                                                             durationMs: 1)))
        XCTAssertNil(wrongKind?.playlistURI)

        let ad = NowPlaying(state: PlaybackState(currentlyPlayingType: "ad"))
        XCTAssertNil(ad?.playlistURI)
    }

    // MARK: Model

    func testLoadKeepsOnlyEditablePlaylists() async {
        let (api, _) = makeAPI(handler: Self.routes(playlists: [
            Self.playlist("mine", owner: "me"), Self.playlist("other", owner: "x"),
        ]))
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)

        await model.load()

        XCTAssertEqual(model.playlists?.map(\.id), ["mine"])
        XCTAssertNil(model.problem)
    }

    func testARecentListIsReusedAndForceReadsAgain() async {
        let (api, recorder) = makeAPI(handler: Self.routes(playlists: [
            Self.playlist("mine", owner: "me"),
        ]))
        var now = Date(timeIntervalSince1970: 0)
        let model = AddToPlaylistModel(api: api, now: { now })

        await model.load()
        XCTAssertEqual(recorder.requests.count, 2, "GET /me and one page")

        await model.load()
        XCTAssertEqual(recorder.requests.count, 2, "Fresh enough: no request")

        now = now.addingTimeInterval(AddToPlaylistModel.maximumListAge + 1)
        await model.load()
        XCTAssertEqual(recorder.requests.count, 3, "Stale: the list again, the user ID is kept")

        await model.load(force: true)
        XCTAssertEqual(recorder.requests.count, 4)
    }

    func testAddingMarksTheRowAndBumpsTheCount() async throws {
        let (api, recorder) = makeAPI(handler: Self.routes(playlists: [
            Self.playlist("mine", owner: "me", count: 3),
        ]))
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)

        await model.add(to: playlist)

        XCTAssertEqual(model.state(of: playlist), .added)
        XCTAssertEqual(model.playlists?.first?.itemCount, 4)
        let posts = recorder.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.count, 1)

        // A second tap does not add a duplicate.
        await model.add(to: playlist)
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testAddedStaysMarkedForTheSameItemOnly() async throws {
        let (api, _) = makeAPI(handler: Self.routes(playlists: [Self.playlist("mine", owner: "me")]))
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)
        await model.add(to: playlist)

        model.open(for: "spotify:track:other1", access: .granted)
        XCTAssertEqual(model.state(of: playlist), .idle)

        model.open(for: trackURI, access: .granted)
        XCTAssertEqual(model.state(of: playlist), .added)
    }

    func testAFailedAddCanBeRetried() async throws {
        let (api, _) = makeAPI(handler: Self.routes(playlists: [Self.playlist("mine", owner: "me")],
                                                    addStatus: 404))
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)

        await model.add(to: playlist)

        XCTAssertEqual(model.state(of: playlist), .failed)
        XCTAssertEqual(model.problem, .addNotFound)
    }

    func testASuccessfulRetryClearsTheEarlierError() async throws {
        let attempts = Counter()
        let (api, _) = makeAPI { request in
            if request.httpMethod == "POST" {
                return attempts.next() == 1 ? (.stub(503), Data())
                    : (.stub(201), Self.json(["snapshot_id": "s"]))
            }
            return try Self.routes(playlists: [Self.playlist("mine", owner: "me")])(request)
        }
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)

        await model.add(to: playlist)
        XCTAssertEqual(model.problem, .connection)

        await model.add(to: playlist)
        XCTAssertEqual(model.state(of: playlist), .added)
        XCTAssertNil(model.problem)
    }

    func testMissingPermissionBlocksAddingUntilGranted() async throws {
        let (api, recorder) = makeAPI(handler: Self.routes(playlists: [Self.playlist("mine", owner: "me")]))
        let model = AddToPlaylistModel(api: api)
        var grant = PlaylistEditingAccess.Grant.missing
        var requests = 0
        let access = PlaylistEditingAccess(grant: { grant }, request: {
            requests += 1
            grant = .granted
            return nil
        })
        model.open(for: trackURI, access: access)
        XCTAssertTrue(model.needsPermission)
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)

        await model.add(to: playlist)
        XCTAssertTrue(recorder.requests.allSatisfy { $0.httpMethod == "GET" })

        await model.requestPermission()

        XCTAssertEqual(requests, 1)
        XCTAssertFalse(model.needsPermission)
        await model.add(to: playlist)
        XCTAssertEqual(model.state(of: playlist), .added)
    }

    func testAFailedPermissionRequestIsShown() async {
        let (api, _) = makeAPI(handler: Self.routes(playlists: []))
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: PlaylistEditingAccess(grant: { .missing },
                                                                request: { .denied }))

        await model.requestPermission()

        XCTAssertTrue(model.needsPermission)
        XCTAssertEqual(model.problem, .permission(.denied))
    }

    func testForbiddenAddWithoutTheScopesAsksForThem() async throws {
        let (api, _) = makeAPI(handler: Self.routes(playlists: [Self.playlist("mine", owner: "me")],
                                                    addStatus: 403))
        let model = AddToPlaylistModel(api: api)
        var grant = PlaylistEditingAccess.Grant.granted
        model.open(for: trackURI, access: PlaylistEditingAccess(grant: { grant },
                                                                request: { nil }))
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)
        grant = .missing

        await model.add(to: playlist)

        XCTAssertTrue(model.needsPermission)
        XCTAssertEqual(model.problem, .addForbidden)
    }

    func testUnknownScopesLetTheUserAddAndAskOnlyAfterAForbiddenAnswer() async throws {
        let (api, _) = makeAPI(handler: Self.routes(playlists: [Self.playlist("mine", owner: "me")],
                                                    addStatus: 403))
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: PlaylistEditingAccess(grant: { .unknown },
                                                                request: { nil }))
        XCTAssertFalse(model.needsPermission)
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)

        await model.add(to: playlist)

        XCTAssertTrue(model.needsPermission, "The only way to fix it is to grant the scopes")
    }

    func testAnAddInFlightSurvivesReopeningTheSheet() async throws {
        let gate = AsyncGate()
        let (api, recorder) = makeAPI { request in
            if request.httpMethod == "POST" {
                gate.waitBlocking()
                return (.stub(201), Self.json(["snapshot_id": "s"]))
            }
            return try Self.routes(playlists: [Self.playlist("mine", owner: "me")])(request)
        }
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)

        let first = Task { await model.add(to: playlist) }
        while model.state(of: playlist) != .adding { await Task.yield() }

        // The sheet closes and opens again for the same item while the request travels.
        model.open(for: trackURI, access: .granted)
        XCTAssertEqual(model.state(of: playlist), .adding)
        await model.add(to: playlist)

        gate.open()
        await first.value
        XCTAssertEqual(model.state(of: playlist), .added)
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    // MARK: Presentation

    func testTheSheetOpensOnTheVisibleScreen() {
        let presentation = PlayerPresentation()
        presentation.showAddToPlaylist()
        XCTAssertTrue(presentation.showsAddToPlaylist)
        XCTAssertFalse(presentation.showsLibraryAddToPlaylist)

        presentation.showsAddToPlaylist = false
        presentation.showsLibrary = true
        presentation.showAddToPlaylist()
        XCTAssertTrue(presentation.showsLibraryAddToPlaylist,
                      "Inside the library: one presented by the player would open behind it")
        XCTAssertFalse(presentation.showsAddToPlaylist)
    }

    // MARK: Controls row

    func testTheGapKeepsTheDesignWhereItFits() {
        let layout = PlayerControlLayout(controls: [.shuffle, .repeatMode, .lyrics, .volume])
        // iPhone 11 Pro Max: 896 − 2 × 48.
        XCTAssertEqual(layout.gap(forWidth: 800), Metrics.Player.controlsGap)
    }

    func testTheGapShrinksOnTheEightPlus() {
        let layout = PlayerControlLayout(controls: [.shuffle, .repeatMode, .lyrics, .volume])
        // iPhone 8 Plus: 736 − 2 × 48. The left group (add + 2 controls) must fit half of
        // what the center leaves: 2 × (3 × 48 + 2g) + 176 + 4g ≤ 640.
        let gap = layout.gap(forWidth: 640)
        XCTAssertEqual(gap, 22)
        XCTAssertLessThanOrEqual(2 * (3 * 48 + 2 * gap) + 176 + 4 * gap, 640)
    }

    func testTheGapNeverGoesBelowTheMinimum() {
        let layout = PlayerControlLayout(controls: [.shuffle, .repeatMode, .lyrics, .volume])
        XCTAssertEqual(layout.gap(forWidth: 300), Metrics.Player.controlsMinimumGap)
    }

    func testFewerControlsKeepTheFullGap() {
        let layout = PlayerControlLayout(controls: [.volume])
        XCTAssertEqual(layout.gap(forWidth: 640), Metrics.Player.controlsGap)
    }
}

/// Holds a stub request until the test opens it. The stub runs on URLSession's own thread.
private final class AsyncGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func waitBlocking() {
        _ = semaphore.wait(timeout: .now() + 5)
    }

    func open() {
        semaphore.signal()
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int { lock.withLock { count += 1; return count } }
}
