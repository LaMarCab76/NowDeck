import XCTest
@testable import Nowdeck

final class SpotifyAPITests: XCTestCase {
    private func makeAPI(
        tokens: FakeTokenProvider = FakeTokenProvider(),
        clock: TestClock = TestClock(),
        sleeps: SleepRecorder = SleepRecorder(),
        handler: @escaping StubURLProtocol.Handler
    ) -> (SpotifyAPI, StubRecorder) {
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let api = SpotifyAPI(tokens: tokens, session: session, now: { clock.now },
                             sleep: { sleeps.record($0) }, jitter: { 0 })
        return (api, recorder)
    }

    func testPlaybackStateRequestAndNothingPlaying() async throws {
        let (api, recorder) = makeAPI { _ in (.stub(204), Data()) }

        let state = try await api.playbackState()

        XCTAssertNil(state, "204 means nothing is playing")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.spotify.com/v1/me/player?additional_types=episode")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-0")
    }

    func testPlaybackStateDecodesAnswer() async throws {
        let body = try Fixture.data("playback-state-playing")
        let (api, _) = makeAPI { _ in (.stub(200), body) }

        let state = try await api.playbackState()

        XCTAssertEqual(state?.device?.name, "MacBook Pro")
        XCTAssertEqual(state?.isPlaying, true)
    }

    func testUnauthorizedRefreshesOnceAndRetries() async throws {
        let tokens = FakeTokenProvider()
        let (api, recorder) = makeAPI(tokens: tokens) { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer token-0" {
                return (.stub(401), spotifyErrorJSON(status: 401, message: "The access token expired"))
            }
            return (.stub(204), Data())
        }

        _ = try await api.playbackState()

        let refreshCount = await tokens.refreshCount
        let rejected = await tokens.rejectedTokens
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(rejected, ["token-0"])
        XCTAssertEqual(recorder.requests.map { $0.value(forHTTPHeaderField: "Authorization") },
                       ["Bearer token-0", "Bearer token-1"])
    }

    func testSecondUnauthorizedIsNotRetriedAgain() async throws {
        let tokens = FakeTokenProvider()
        let (api, recorder) = makeAPI(tokens: tokens) { _ in (.stub(401), Data()) }

        await assertThrows(.unauthorized) { _ = try await api.playbackState() }

        let refreshCount = await tokens.refreshCount
        XCTAssertEqual(refreshCount, 1, "Only one refresh per request")
        XCTAssertEqual(recorder.requests.count, 2)
    }

    func testRateLimitUsesRetryAfterAndBlocksUntilItPasses() async throws {
        let clock = TestClock()
        let (api, recorder) = makeAPI(clock: clock) { _ in
            (.stub(429, headers: ["Retry-After": "7"]),
             spotifyErrorJSON(status: 429, message: "Quota exceeded", reason: "QUOTA_EXCEEDED"))
        }

        await assertThrows(.rateLimited(retryAfter: 7, quotaExceeded: true)) {
            _ = try await api.playbackState()
        }
        XCTAssertEqual(recorder.requests.count, 1)

        // Before Retry-After passes, calls fail without touching the network.
        clock.advance(5)
        await assertThrows(.rateLimited(retryAfter: 2, quotaExceeded: true)) {
            _ = try await api.playbackState()
        }
        XCTAssertEqual(recorder.requests.count, 1)

        // After it, requests go out again.
        clock.advance(2)
        await assertThrows(.rateLimited(retryAfter: 7, quotaExceeded: true)) {
            _ = try await api.playbackState()
        }
        XCTAssertEqual(recorder.requests.count, 2)
    }

    func testRateLimitWithoutHeaderUsesDefaultWait() async throws {
        let (api, _) = makeAPI { _ in (.stub(429), Data()) }

        await assertThrows(.rateLimited(retryAfter: SpotifyAPI.defaultRetryAfter,
                                        quotaExceeded: false)) {
            _ = try await api.playbackState()
        }
    }

    func testServerErrorOnReadIsRetriedWithGrowingWaits() async throws {
        let sleeps = SleepRecorder()
        let attempts = SleepRecorder() // used as a thread-safe counter
        let (api, recorder) = makeAPI(sleeps: sleeps) { _ in
            attempts.record(1)
            return attempts.sleeps.count < 3 ? (.stub(503), Data()) : (.stub(204), Data())
        }

        let state = try await api.playbackState()

        XCTAssertNil(state)
        XCTAssertEqual(recorder.requests.count, 3)
        XCTAssertEqual(sleeps.sleeps, SpotifyAPI.serverRetryDelays)
    }

    func testServerErrorGivesUpAfterRetries() async throws {
        let sleeps = SleepRecorder()
        let (api, recorder) = makeAPI(sleeps: sleeps) { _ in (.stub(500), Data()) }

        await assertThrows(.server(status: 500)) { _ = try await api.playbackState() }
        XCTAssertEqual(recorder.requests.count, 1 + SpotifyAPI.serverRetryDelays.count)
    }

    func testServerErrorOnCommandIsNotRetried() async throws {
        let sleeps = SleepRecorder()
        let (api, recorder) = makeAPI(sleeps: sleeps) { _ in (.stub(502), Data()) }

        await assertThrows(.server(status: 502)) {
            _ = try await api.send(SpotifyAPI.Request(method: "POST", path: "/me/player/next"))
        }
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertTrue(sleeps.sleeps.isEmpty)
    }

    func testForbiddenCarriesMessage() async throws {
        let (api, _) = makeAPI { _ in
            (.stub(403), spotifyErrorJSON(status: 403, message: "User not registered"))
        }
        await assertThrows(.forbidden(message: "User not registered")) {
            _ = try await api.playbackState()
        }
    }

    func testNetworkErrorIsReported() async throws {
        let (api, _) = makeAPI { _ in throw URLError(.notConnectedToInternet) }
        await assertThrows(.network(.notConnectedToInternet)) {
            _ = try await api.playbackState()
        }
    }

    func testPlaylistNameAsksOnlyForTheName() async throws {
        let (api, recorder) = makeAPI { _ in (.stub(200), Data(#"{"name":"Para laburar"}"#.utf8)) }

        let name = try await api.playlistName(id: "3cEYpjA9oz9GiPac4AsH4n")

        XCTAssertEqual(name, "Para laburar")
        XCTAssertEqual(recorder.requests.first?.url?.absoluteString,
                       "https://api.spotify.com/v1/playlists/3cEYpjA9oz9GiPac4AsH4n?fields=name")
    }

    func testPlaylistNotFound() async throws {
        let (api, _) = makeAPI { _ in (.stub(404), spotifyErrorJSON(status: 404, message: "Not found.")) }
        await assertThrows(.notFound(message: "Not found.")) {
            _ = try await api.playlistName(id: "37i9dQZF1DXcBWIGoYBM5M")
        }
    }

    // MARK: Helpers

    private func assertThrows(_ expected: SpotifyAPIError, file: StaticString = #filePath,
                              line: UInt = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SpotifyAPIError, expected, file: file, line: line)
        }
    }
}
