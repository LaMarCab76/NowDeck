import UIKit
import XCTest
@testable import Nowdeck

@MainActor
final class PlayerModelTests: XCTestCase {
    /// One stub session answers the API and the artwork CDN.
    private func makeModel(
        clock: TestClock = TestClock(),
        handler: @escaping StubURLProtocol.Handler
    ) -> (PlayerModel, StubRecorder) {
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, now: { clock.now },
                             sleep: { _ in }, jitter: { 0 })
        let model = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session),
                                now: { clock.now })
        return (model, recorder)
    }

    private static func pngData(_ hex: String) -> Data {
        let color = RGBColor(hex: hex)!
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.pngData { context in
            UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func testNothingPlaying() async {
        let (model, _) = makeModel { _ in (.stub(204), Data()) }
        let delay = await model.poll()
        XCTAssertEqual(model.status, .nothingPlaying)
        XCTAssertEqual(delay, 10)
    }

    func testPlayingStateWithPlaylistNameAndArtwork() async throws {
        let playback = try Fixture.data("playback-state-playing")
        let png = Self.pngData("#1E3A5C")
        let (model, recorder) = makeModel { request in
            switch request.url?.host {
            case "i.scdn.co": return (.stub(200), png)
            default:
                if request.url?.path == "/v1/playlists/3cEYpjA9oz9GiPac4AsH4n" {
                    return (.stub(200), Data(#"{"name":"Para laburar"}"#.utf8))
                }
                return (.stub(200), playback)
            }
        }

        let delay = await model.poll()

        XCTAssertEqual(delay, 3, "Playing: poll every 3 s")
        XCTAssertEqual(model.status, .active)
        XCTAssertEqual(model.nowPlaying?.title, "Vereda Mojada")
        XCTAssertEqual(model.origin?.kind, .playlist)

        // The playlist name and the artwork arrive in the background.
        try await waitUntil { model.origin?.name == "Para laburar" && model.artwork != nil }
        XCTAssertNotNil(model.artworkColor)

        // A second poll reuses the cached name: one playlist request in total.
        await model.poll()
        let playlistRequests = recorder.requests.filter { $0.url?.path.hasPrefix("/v1/playlists") == true }
        XCTAssertEqual(playlistRequests.count, 1)
        XCTAssertEqual(model.origin?.name, "Para laburar")
    }

    func testItemStartsCountTheSameTrackStartingAgain() async throws {
        let fixture = try Fixture.data("playback-state-playing") // 84 s of 227 s, playing
        let progress = LockedValue(84_000)
        let clock = TestClock()
        let (model, _) = makeModel(clock: clock) { request in
            if request.url?.host == "i.scdn.co" { return (.stub(404), Data()) }
            if request.url?.path.hasPrefix("/v1/playlists") == true { return (.stub(404), Data()) }
            var state = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
            state["progress_ms"] = progress.value
            return (.stub(200), try JSONSerialization.data(withJSONObject: state))
        }

        await model.poll()
        XCTAssertEqual(model.itemStarts, 1, "The first item counts as a start")

        // 3 s later, at 86 s: about where it should be (87 s), not a new start.
        clock.advance(3)
        progress.value = 86_000
        await model.poll()
        XCTAssertEqual(model.itemStarts, 1)

        // 3 s later the same track is back at 1 s: its second copy in the queue started.
        clock.advance(3)
        progress.value = 1_000
        await model.poll()
        XCTAssertEqual(model.itemStarts, 2)
        XCTAssertEqual(model.nowPlaying?.title, "Vereda Mojada")
    }

    func testUnreadablePlaylistShowsOnlyTheType() async throws {
        let playback = try Fixture.data("playback-state-playing")
        let (model, recorder) = makeModel { request in
            if request.url?.host == "i.scdn.co" { return (.stub(404), Data()) }
            if request.url?.path.hasPrefix("/v1/playlists") == true { return (.stub(404), Data()) }
            return (.stub(200), playback)
        }

        await model.poll()
        try await waitUntil {
            recorder.requests.contains { $0.url?.path.hasPrefix("/v1/playlists") == true }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        await model.poll()

        XCTAssertNil(model.origin?.name)
        let playlistRequests = recorder.requests.filter { $0.url?.path.hasPrefix("/v1/playlists") == true }
        XCTAssertEqual(playlistRequests.count, 1, "A 404 is not asked again")
    }

    func testForbiddenShowsAccessProblem() async {
        let (model, _) = makeModel { _ in (.stub(403), Data()) }
        let delay = await model.poll()
        XCTAssertEqual(model.status, .accessDenied)
        XCTAssertEqual(delay, PollingPolicy().forbiddenInterval)
    }

    func testFailureKeepsLastStateAndMarksItStale() async throws {
        let playback = try Fixture.data("playback-state-playing")
        let fail = SleepRecorder() // thread-safe flag: non-empty = fail
        let (model, _) = makeModel { request in
            if request.url?.host != "api.spotify.com" { return (.stub(404), Data()) }
            if request.url?.path.hasPrefix("/v1/playlists") == true { return (.stub(404), Data()) }
            if !fail.sleeps.isEmpty { throw URLError(.notConnectedToInternet) }
            return (.stub(200), playback)
        }

        await model.poll()
        XCTAssertEqual(model.freshness, .live)

        fail.record(1)
        let delay = await model.poll()
        XCTAssertEqual(model.status, .active, "The last state stays on screen")
        XCTAssertEqual(model.nowPlaying?.title, "Vereda Mojada")
        XCTAssertEqual(model.freshness, .stale)
        XCTAssertGreaterThanOrEqual(delay, 3)
    }

    func testFirstPollFailingShowsUnavailable() async {
        let (model, _) = makeModel { _ in throw URLError(.notConnectedToInternet) }
        await model.poll()
        XCTAssertEqual(model.status, .unavailable)
    }

    func testQuotaExceededSlowsPollingDown() async throws {
        let clock = TestClock()
        let calls = SleepRecorder()
        let (model, _) = makeModel(clock: clock) { _ in
            calls.record(1)
            if calls.sleeps.count == 1 {
                return (.stub(429, headers: ["Retry-After": "4"]),
                        spotifyErrorJSON(status: 429, message: "x", reason: "QUOTA_EXCEEDED"))
            }
            return (.stub(204), Data())
        }

        let first = await model.poll()
        XCTAssertEqual(model.freshness, .quotaLimited)
        XCTAssertGreaterThanOrEqual(first, 4)

        clock.advance(5)
        let next = await model.poll()
        XCTAssertEqual(next, PollingPolicy().quotaIdleInterval)
        XCTAssertEqual(model.freshness, .quotaLimited)

        clock.advance(PollingPolicy().quotaCooldown)
        let later = await model.poll()
        XCTAssertEqual(later, 10)
        XCTAssertEqual(model.freshness, .live)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

/// A value the stub reads on the loading thread while the test changes it.
private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
