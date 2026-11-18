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
                                             count: Int = 3,
                                             snapshot: String = "v1") -> [String: Any] {
        ["id": id, "name": "Lista \(id)", "uri": "spotify:playlist:\(id)",
         "collaborative": collaborative, "owner": ["id": owner],
         "items": ["total": count], "images": [], "snapshot_id": snapshot]
    }

    /// One page of `GET /playlists/{id}/items` with these URIs, in the February 2026 shape.
    nonisolated private static func itemsPage(_ uris: [String]) -> Data {
        json(["items": uris.map { ["is_local": false, "item": ["type": "track", "uri": $0]] },
              "limit": 50, "offset": 0, "total": uris.count, "next": NSNull()])
    }

    /// `GET /me` answers `me`; `GET /me/playlists` answers one page with `playlists`;
    /// `GET /playlists/{id}/items` answers the URIs in `items` (none if missing);
    /// `POST …/items` answers `addStatus`.
    nonisolated private static func routes(
        playlists: [[String: Any]],
        items: [String: [String]] = [:],
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
            case ("GET", _) where path.hasPrefix("/v1/playlists/") && path.hasSuffix("/items"):
                let id = path.split(separator: "/")[2]
                return (.stub(200), itemsPage(items[String(id)] ?? []))
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
            switch Self.offset(of: request) {
            case 0:
                return (.stub(200), Self.json([
                    "items": [Self.playlist("a", owner: "me")], "limit": 50, "offset": 0,
                    "next": "https://api.spotify.com/v1/me/playlists?offset=50"]))
            case 50:
                return (.stub(200), Self.json([
                    "items": [Self.playlist("b", owner: "me")], "limit": 50, "offset": 50,
                    "next": NSNull()]))
            default:
                return (.stub(400), Data())
            }
        }

        let playlists = try await api.allSavedPlaylists()

        XCTAssertEqual(playlists.map(\.id), ["a", "b"])
        XCTAssertEqual(recorder.requests.map(Self.offset(of:)), [0, 50])
        XCTAssertTrue(recorder.requests[0].url!.absoluteString.contains("limit=50"))
    }

    nonisolated private static func offset(of request: URLRequest) -> Int? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "offset" }?.value.flatMap { Int($0) }
    }

    func testAllPlaylistsStopsAfterTheMaximumPages() async throws {
        let (api, recorder) = makeAPI { request in
            // Pages that always say there is more.
            (.stub(200), Self.json(["items": [], "limit": 50,
                                    "offset": Self.offset(of: request) ?? 0,
                                    "next": "https://api.spotify.com/v1/me/playlists"]))
        }

        _ = try await api.allSavedPlaylists(maximumPages: 3)

        XCTAssertEqual(recorder.requests.map(Self.offset(of:)), [0, 50, 100])
    }

    func testAPageThatDoesNotMoveForwardIsAnError() async {
        let (api, recorder) = makeAPI { _ in
            (.stub(200), Self.json(["items": [], "limit": 50, "offset": 0,
                                    "next": "https://api.spotify.com/v1/me/playlists"]))
        }

        do {
            _ = try await api.allSavedPlaylists()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SpotifyAPIError, .invalidResponse)
        }
        XCTAssertEqual(recorder.requests.count, 2)
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
        let mine = try XCTUnwrap(editable.first { $0.id == "mine" })
        let shared = try XCTUnwrap(editable.first { $0.id == "shared" })
        XCTAssertFalse(mine.isCollaborative)
        XCTAssertTrue(shared.isCollaborative)
        XCTAssertEqual(mine.itemCount, 3)
        XCTAssertEqual(mine.pageURL?.absoluteString, "https://open.spotify.com/playlist/mine")
    }

    func testAnIneligibleCopyDoesNotHideALaterEditableOne() {
        let editable = EditablePlaylist.editable(from: [
            SimplifiedPlaylist(id: "p", name: "P"),
            SimplifiedPlaylist(id: "p", name: "P", owner: .init(id: "me")),
        ], userID: "me")
        XCTAssertEqual(editable.map(\.id), ["p"])
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
        let (api, recorder) = makeAPI { request in
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

        XCTAssertEqual(model.state(of: playlist), .failed)

        await model.add(to: playlist)
        XCTAssertEqual(model.state(of: playlist), .added)
        XCTAssertNil(model.problem)
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "POST" }.count, 2,
                       "A failed row accepts a second tap")
    }

    func testGrantingThePermissionReadsAListThatFailedBefore() async throws {
        let online = Counter()
        let (api, _) = makeAPI { request in
            if online.next() <= 1 { throw URLError(.notConnectedToInternet) }
            return try Self.routes(playlists: [Self.playlist("mine", owner: "me")])(request)
        }
        let model = AddToPlaylistModel(api: api)
        var grant = PlaylistEditingAccess.Grant.missing
        model.open(for: trackURI, access: PlaylistEditingAccess(grant: { grant }, request: {
            grant = .granted
            return nil
        }))
        await model.load()
        XCTAssertNil(model.playlists)

        await model.requestPermission()

        XCTAssertEqual(model.playlists?.map(\.id), ["mine"])
        XCTAssertNil(model.problem)
    }

    func testAFailureForAnotherItemDoesNotShowInTheOpenSheet() async throws {
        let gate = AsyncGate()
        defer { gate.open() }  // Never leave the stub blocked, even if the test fails.
        let (api, _) = makeAPI { request in
            if request.httpMethod == "POST" {
                gate.waitBlocking()
                return (.stub(404), spotifyErrorJSON(status: 404, message: "No"))
            }
            return try Self.routes(playlists: [Self.playlist("mine", owner: "me")])(request)
        }
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)

        let first = Task { await model.add(to: playlist) }
        try await waitUntil("the add to start") { model.state(of: playlist) == .adding }
        model.open(for: "spotify:track:other1", access: .granted)
        gate.open()
        await first.value

        XCTAssertNil(model.problem)
        model.open(for: trackURI, access: .granted)
        XCTAssertEqual(model.state(of: playlist), .idle, "Failures are cleared on opening")
    }

    func testACountReadWhileAnAddWasOutIsDropped() async throws {
        let gate = AsyncGate()
        defer { gate.open() }  // Never leave the stub blocked, even if the test fails.
        let (api, _) = makeAPI { request in
            if request.httpMethod == "POST" {
                gate.waitBlocking()
                return (.stub(201), Self.json(["snapshot_id": "s"]))
            }
            return try Self.routes(playlists: [Self.playlist("mine", owner: "me", count: 10)])(request)
        }
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)
        await model.load()
        let playlist = try XCTUnwrap(model.playlists?.first)

        let adding = Task { await model.add(to: playlist) }
        try await waitUntil("the add to start") { model.state(of: playlist) == .adding }
        await model.load(force: true)
        gate.open()
        await adding.value

        XCTAssertNil(model.playlists?.first?.itemCount,
                     "The read may or may not include the add: no guess")
        await model.load(force: true)
        XCTAssertEqual(model.playlists?.first?.itemCount, 10, "A read after the add is trusted")
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
        defer { gate.open() }  // Never leave the stub blocked, even if the test fails.
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
        try await waitUntil("the add to start") { model.state(of: playlist) == .adding }

        // The sheet closes and opens again for the same item while the request travels.
        model.open(for: trackURI, access: .granted)
        XCTAssertEqual(model.state(of: playlist), .adding)
        await model.add(to: playlist)

        gate.open()
        await first.value
        XCTAssertEqual(model.state(of: playlist), .added)
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    // MARK: Already in, first

    nonisolated private static func itemReads(_ requests: [URLRequest]) -> [String] {
        requests.compactMap { request in
            let path = request.url?.path ?? ""
            guard request.httpMethod == "GET", path.hasPrefix("/v1/playlists/") else { return nil }
            return String(path.split(separator: "/")[2])
        }
    }

    func testItemURIsFollowThePagesAndReadBothNames() async throws {
        let (api, recorder) = makeAPI { request in
            switch Self.offset(of: request) {
            case 0:
                return (.stub(200), Self.json([
                    "items": [["item": ["uri": "spotify:track:a"]],
                              ["track": ["uri": "spotify:track:b"]],
                              ["item": NSNull()]],
                    "limit": 50, "offset": 0,
                    "next": "https://api.spotify.com/v1/playlists/p/items?offset=50"]))
            default:
                return (.stub(200), Self.json([
                    "items": [["item": ["type": "episode", "uri": "spotify:episode:c"]]],
                    "limit": 50, "offset": 50, "next": NSNull()]))
            }
        }

        let uris = try await api.playlistItemURIs(playlistID: "p")

        XCTAssertEqual(uris, ["spotify:track:a", "spotify:track:b", "spotify:episode:c"])
        XCTAssertEqual(recorder.requests.map(Self.offset(of:)), [0, 50])
        let url = recorder.requests[0].url!.absoluteString
        XCTAssertTrue(url.hasPrefix("https://api.spotify.com/v1/playlists/p/items?"))
        XCTAssertTrue(url.contains("limit=50"))
        XCTAssertTrue(url.contains("additional_types=track,episode"))
    }

    func testTheSearchIgnoresCaseAndAccentsAndKeepsTheGroups() {
        func playlist(_ id: String, _ name: String) -> EditablePlaylist {
            EditablePlaylist(id: id, name: name, isCollaborative: false)
        }
        let all = [playlist("1", "Canción de cuna"), playlist("2", "Rock nacional"),
                   playlist("3", "CANCIONES tristes"), playlist("4", "Otra")]

        let everything = PlaylistSections(playlists: all, containing: ["3"], query: "  ")
        XCTAssertEqual(everything.alreadyIn.map(\.id), ["3"])
        XCTAssertEqual(everything.others.map(\.id), ["1", "2", "4"],
                       "Spotify's order inside each group")

        let filtered = PlaylistSections(playlists: all, containing: ["3"], query: "cancion")
        XCTAssertEqual(filtered.alreadyIn.map(\.id), ["3"])
        XCTAssertEqual(filtered.others.map(\.id), ["1"])

        XCTAssertTrue(PlaylistSections(playlists: all, containing: [], query: "jazz").isEmpty)
    }

    func testPlaylistsThatHoldTheItemAreFoundAndCannotGetASecondCopy() async throws {
        let (api, recorder) = makeAPI(handler: Self.routes(
            playlists: [Self.playlist("a", owner: "me"), Self.playlist("b", owner: "me"),
                        Self.playlist("c", owner: "x", collaborative: true)],
            items: ["b": ["spotify:track:other1"], "c": [trackURI, "spotify:track:other2"]]))
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)

        await model.prepare()

        XCTAssertTrue(model.isMembershipReady)
        XCTAssertFalse(model.membershipIncomplete)
        XCTAssertEqual(model.containingIDs, ["c"])
        let sections = PlaylistSections(playlists: model.playlists ?? [],
                                        containing: model.containingIDs, query: "")
        XCTAssertEqual(sections.alreadyIn.map(\.id), ["c"])
        XCTAssertEqual(sections.others.map(\.id), ["a", "b"])
        XCTAssertEqual(Set(Self.itemReads(recorder.requests)), ["a", "b", "c"])

        let c = try XCTUnwrap(model.playlists?.first { $0.id == "c" })
        XCTAssertEqual(model.state(of: c), .added)
        await model.add(to: c)
        XCTAssertFalse(recorder.requests.contains { $0.httpMethod == "POST" })
    }

    func testOnlyPlaylistsThatChangedAreReadAgain() async throws {
        let snapshots = SnapshotBox(["a": "v1", "b": "v1"])
        let uri = trackURI
        let (api, recorder) = makeAPI { request in
            let list = [Self.playlist("a", owner: "me", snapshot: snapshots["a"]),
                        Self.playlist("b", owner: "me", snapshot: snapshots["b"])]
            let inB = snapshots["b"] == "v2" ? [uri, "spotify:track:x"] : ["spotify:track:x"]
            return try Self.routes(playlists: list, items: ["b": inB])(request)
        }
        var now = Date(timeIntervalSince1970: 0)
        let model = AddToPlaylistModel(api: api, now: { now })
        model.open(for: trackURI, access: .granted)
        await model.prepare()
        XCTAssertEqual(Self.itemReads(recorder.requests).count, 2)
        XCTAssertEqual(model.containingIDs, [])

        // Another opening for another track: nothing is read again.
        model.open(for: "spotify:track:x", access: .granted)
        XCTAssertTrue(model.isMembershipReady, "Fresh list, every playlist read: no wait")
        XCTAssertEqual(model.containingIDs, ["b"])
        await model.prepare()
        XCTAssertEqual(Self.itemReads(recorder.requests).count, 2)

        // The track was added to "b" in Spotify: only "b" is read again.
        snapshots["b"] = "v2"
        now = now.addingTimeInterval(AddToPlaylistModel.maximumListAge + 1)
        model.open(for: trackURI, access: .granted)
        XCTAssertFalse(model.isMembershipReady, "The list is stale: wait for the new order")
        await model.prepare()
        XCTAssertEqual(Self.itemReads(recorder.requests).suffix(1), ["b"])
        XCTAssertEqual(Self.itemReads(recorder.requests).count, 3)
        XCTAssertEqual(model.containingIDs, ["b"])
    }

    func testAPlaylistThatCannotBeReadIsListedAndFlagged() async throws {
        let uri = trackURI
        let (api, _) = makeAPI { request in
            if request.url?.path == "/v1/playlists/bad/items" { return (.stub(404), Data()) }
            return try Self.routes(playlists: [Self.playlist("bad", owner: "me"),
                                               Self.playlist("good", owner: "me")],
                                   items: ["good": [uri]])(request)
        }
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)

        await model.prepare()

        XCTAssertTrue(model.isMembershipReady)
        XCTAssertTrue(model.membershipIncomplete)
        XCTAssertEqual(model.containingIDs, ["good"])
        XCTAssertEqual(model.playlists?.map(\.id), ["bad", "good"])
    }

    func testOldContentsDoNotConfirmTheItemWhenTheNewVersionCannotBeRead() async throws {
        let snapshots = SnapshotBox(["b": "v1"])
        let uri = trackURI
        let (api, _) = makeAPI { request in
            if request.url?.path == "/v1/playlists/b/items", snapshots["b"] == "v2" {
                return (.stub(404), Data())
            }
            return try Self.routes(playlists: [Self.playlist("b", owner: "me",
                                                             snapshot: snapshots["b"])],
                                   items: ["b": [uri]])(request)
        }
        var now = Date(timeIntervalSince1970: 0)
        let model = AddToPlaylistModel(api: api, now: { now })
        model.open(for: trackURI, access: .granted)
        await model.prepare()
        XCTAssertEqual(model.containingIDs, ["b"])

        // The playlist changed in Spotify (the track may be gone) and can't be read now.
        snapshots["b"] = "v2"
        now = now.addingTimeInterval(AddToPlaylistModel.maximumListAge + 1)
        model.open(for: trackURI, access: .granted)
        await model.prepare()

        XCTAssertEqual(model.containingIDs, [])
        XCTAssertTrue(model.membershipIncomplete)
        let b = try XCTUnwrap(model.playlists?.first)
        XCTAssertEqual(model.state(of: b), .idle, "The user can still add it")
    }

    func testATapDuringARefreshWaitsAndDoesNotAddASecondCopy() async throws {
        let snapshots = SnapshotBox(["a": "v1"])
        let gate = AsyncGate()
        defer { gate.open() }  // Never leave the stub blocked, even if the test fails.
        let uri = trackURI
        let (api, recorder) = makeAPI { request in
            let changed = snapshots["a"] == "v2"
            if request.url?.path == "/v1/playlists/a/items", changed { gate.waitBlocking() }
            if request.httpMethod == "POST" { return (.stub(201), Self.json(["snapshot_id": "v3"])) }
            return try Self.routes(playlists: [Self.playlist("a", owner: "me",
                                                             snapshot: snapshots["a"])],
                                   items: ["a": changed ? [uri] : []])(request)
        }
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)
        await model.prepare()
        let a = try XCTUnwrap(model.playlists?.first)
        XCTAssertEqual(model.state(of: a), .idle)

        // The track was added to "a" elsewhere; the user pulls to refresh and taps "a".
        snapshots["a"] = "v2"
        let refresh = Task { await model.prepare(force: true) }
        try await waitUntil("the refresh to read the playlist") {
            model.membershipProgress != nil
        }
        let tap = Task { await model.add(to: a) }
        try await waitUntil("the tap to wait") { model.state(of: a) == .adding }
        gate.open()
        await refresh.value
        await tap.value

        XCTAssertFalse(recorder.requests.contains { $0.httpMethod == "POST" })
        XCTAssertEqual(model.state(of: a), .added)
    }

    func testAnAddThatFinishesDuringAReadIsNotLost() async throws {
        // The stub serves one request at a time, so nothing may block its thread. The add
        // and the read are held with async waits instead: the POST gets a 401 and waits for
        // the token refresh, the read gets a 503 and waits for its retry.
        let snapshots = SnapshotBox(["a": "v1"])
        let posts = Counter()
        let changedReads = Counter()
        let tokens = HeldTokenProvider()
        let retry = AsyncSignal()
        let (session, _) = StubURLProtocol.session { request in
            if request.httpMethod == "POST" {
                return posts.next() == 1 ? (.stub(401), Data())
                    : (.stub(201), Self.json(["snapshot_id": "v3"]))
            }
            if request.url?.path == "/v1/playlists/a/items", snapshots["a"] == "v2",
               changedReads.next() == 1 {
                return (.stub(503), Data())
            }
            return try Self.routes(playlists: [Self.playlist("a", owner: "me",
                                                             snapshot: snapshots["a"])])(request)
        }
        let api = SpotifyAPI(tokens: tokens, session: session, now: { Date() },
                             sleep: { _ in await retry.wait() }, jitter: { 0 })
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)
        await model.prepare()
        let a = try XCTUnwrap(model.playlists?.first)

        let adding = Task { await model.add(to: a) }
        try await waitUntil("the add to wait for a token") { await tokens.release.isWaiting }
        snapshots["a"] = "v2"  // Changed elsewhere: the refresh reads it again.
        let refresh = Task { await model.prepare(force: true) }
        try await waitUntil("the read to wait for its retry") { await retry.isWaiting }
        await tokens.release.open()
        await adding.value
        XCTAssertEqual(model.state(of: a), .added)
        await retry.open()
        await refresh.value

        model.open(for: trackURI, access: .granted)
        await model.prepare()
        XCTAssertEqual(model.containingIDs, ["a"],
                       "The read predates the add: the add must not be lost from the cache")
    }

    func testEmptyPlaylistsNeedNoRequest() async {
        let (api, recorder) = makeAPI(handler: Self.routes(playlists: [
            Self.playlist("empty", owner: "me", count: 0),
        ]))
        let model = AddToPlaylistModel(api: api)
        model.open(for: trackURI, access: .granted)

        await model.prepare()

        XCTAssertTrue(model.isMembershipReady)
        XCTAssertEqual(Self.itemReads(recorder.requests), [])
    }

    func testAnAddedRowStaysInPlaceAndComesFirstNextTime() async throws {
        let snapshots = SnapshotBox(["a": "v1", "b": "v1"])
        let uri = trackURI
        let (api, recorder) = makeAPI { request in
            if request.httpMethod == "POST" {
                snapshots["b"] = "v2"
                return (.stub(201), Self.json(["snapshot_id": "v2"]))
            }
            let list = [Self.playlist("a", owner: "me", snapshot: snapshots["a"]),
                        Self.playlist("b", owner: "me", snapshot: snapshots["b"])]
            let inB = snapshots["b"] == "v2" ? [uri] : []
            return try Self.routes(playlists: list, items: ["b": inB])(request)
        }
        var now = Date(timeIntervalSince1970: 0)
        let model = AddToPlaylistModel(api: api, now: { now })
        model.open(for: trackURI, access: .granted)
        await model.prepare()
        let b = try XCTUnwrap(model.playlists?.last)

        await model.add(to: b)

        XCTAssertEqual(model.state(of: b), .added)
        XCTAssertEqual(model.containingIDs, [], "No row moves while the sheet is open")

        model.open(for: trackURI, access: .granted)
        XCTAssertTrue(model.isMembershipReady)
        XCTAssertEqual(model.containingIDs, ["b"])
        await model.prepare()
        XCTAssertEqual(Self.itemReads(recorder.requests).count, 2,
                       "Same list as before: the cached contents plus the add are used")

        // The next list read brings the new version: the playlist is read again instead of
        // trusting contents that may miss changes made elsewhere.
        now = now.addingTimeInterval(AddToPlaylistModel.maximumListAge + 1)
        model.open(for: trackURI, access: .granted)
        await model.prepare()
        XCTAssertEqual(Self.itemReads(recorder.requests).suffix(1), ["b"])
        XCTAssertEqual(model.containingIDs, ["b"])
    }

    func testGrantingThePermissionAlsoChecksWhereTheItemIs() async throws {
        let online = Counter()
        let uri = trackURI
        let (api, _) = makeAPI { request in
            if online.next() <= 1 { throw URLError(.notConnectedToInternet) }
            return try Self.routes(playlists: [Self.playlist("a", owner: "me"),
                                               Self.playlist("b", owner: "me")],
                                   items: ["b": [uri]])(request)
        }
        let model = AddToPlaylistModel(api: api)
        var grant = PlaylistEditingAccess.Grant.missing
        model.open(for: trackURI, access: PlaylistEditingAccess(grant: { grant }, request: {
            grant = .granted
            return nil
        }))
        await model.prepare()
        XCTAssertNil(model.playlists)
        XCTAssertFalse(model.isMembershipReady)

        await model.requestPermission()

        XCTAssertTrue(model.isMembershipReady, "Otherwise the sheet would wait forever")
        XCTAssertEqual(model.containingIDs, ["b"])
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

/// A one-shot async signal: `wait()` suspends (without blocking a thread) until `open()`.
private actor AsyncSignal {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isWaiting: Bool { !waiters.isEmpty }

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// Holds the token refresh that follows a `401` until the test releases it.
private actor HeldTokenProvider: AccessTokenProvider {
    let release = AsyncSignal()

    func validAccessToken() async throws -> String { "token" }

    func accessTokenAfterUnauthorized(rejectedToken: String) async throws -> String {
        await release.wait()
        return "token-2"
    }
}

/// Snapshot IDs that a test changes while the stub reads them from URLSession's thread.
private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    init(_ values: [String: String]) { self.values = values }

    subscript(id: String) -> String {
        get { lock.withLock { values[id] ?? "" } }
        set { lock.withLock { values[id] = newValue } }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int { lock.withLock { count += 1; return count } }
}
