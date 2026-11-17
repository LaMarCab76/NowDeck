import XCTest
@testable import Nowdeck

/// Requests of the playback commands, as listed in the Web API reference (checked
/// 2026-11-17).
final class PlaybackCommandTests: XCTestCase {
    private func describe(_ command: PlaybackCommand) -> (String, String, [String: String], Bool) {
        let request = command.request
        let query = Dictionary(uniqueKeysWithValues: request.query.map { ($0.name, $0.value ?? "") })
        return (request.method, request.path, query, request.body == nil)
    }

    func testPlayAndPause() {
        XCTAssertTrue(describe(.play) == ("PUT", "/me/player/play", [:], true))
        XCTAssertTrue(describe(.pause) == ("PUT", "/me/player/pause", [:], true))
    }

    func testNextAndPreviousArePosts() {
        XCTAssertTrue(describe(.next) == ("POST", "/me/player/next", [:], true))
        XCTAssertTrue(describe(.previous) == ("POST", "/me/player/previous", [:], true))
    }

    func testShuffle() {
        XCTAssertTrue(describe(.shuffle(true)) == ("PUT", "/me/player/shuffle", ["state": "true"], true))
        XCTAssertTrue(describe(.shuffle(false)) == ("PUT", "/me/player/shuffle", ["state": "false"], true))
    }

    func testRepeat() {
        XCTAssertEqual(describe(.repeatMode(.off)).2, ["state": "off"])
        XCTAssertEqual(describe(.repeatMode(.context)).2, ["state": "context"])
        XCTAssertEqual(describe(.repeatMode(.track)).2, ["state": "track"])
        XCTAssertEqual(describe(.repeatMode(.track)).1, "/me/player/repeat")
        XCTAssertEqual(describe(.repeatMode(.track)).0, "PUT")
    }

    func testVolumeIsClampedToTheDocumentedRange() {
        XCTAssertTrue(describe(.volume(62)) == ("PUT", "/me/player/volume", ["volume_percent": "62"], true))
        XCTAssertEqual(describe(.volume(130)).2, ["volume_percent": "100"])
        XCTAssertEqual(describe(.volume(-5)).2, ["volume_percent": "0"])
    }

    func testSeek() {
        XCTAssertTrue(describe(.seek(positionMs: 25_000)) == ("PUT", "/me/player/seek", ["position_ms": "25000"], true))
        XCTAssertEqual(describe(.seek(positionMs: -10)).2, ["position_ms": "0"])
    }

    // MARK: Through the client

    func testCommandReachesTheAPIWithTheToken() async throws {
        let (session, recorder) = StubURLProtocol.session { _ in (.stub(204), Data()) }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, sleep: { _ in },
                             jitter: { 0 })

        try await api.sendCommand(.repeatMode(.context))

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.spotify.com/v1/me/player/repeat?state=context")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-0")
    }

    func testCommandsAreNotRetriedAfterAServerError() async throws {
        let (session, recorder) = StubURLProtocol.session { _ in (.stub(502), Data()) }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, sleep: { _ in },
                             jitter: { 0 })

        do {
            try await api.sendCommand(.next)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SpotifyAPIError, .server(status: 502))
        }
        XCTAssertEqual(recorder.requests.count, 1, "Repeating next would skip two tracks")
    }

    func testNoActiveDeviceIsNotFound() async throws {
        let (session, _) = StubURLProtocol.session { _ in
            (.stub(404), spotifyErrorJSON(status: 404, message: "Player command failed: No active device found"))
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, sleep: { _ in },
                             jitter: { 0 })

        do {
            try await api.sendCommand(.play)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SpotifyAPIError,
                           .notFound(message: "Player command failed: No active device found"))
        }
    }
}
