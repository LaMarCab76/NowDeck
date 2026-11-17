import Foundation
import XCTest
@testable import Nowdeck

/// Token provider that hands out `token-0`, then `token-1` after each refresh.
actor FakeTokenProvider: AccessTokenProvider {
    private(set) var refreshCount = 0
    private(set) var rejectedTokens: [String] = []

    var current: String { "token-\(refreshCount)" }

    func validAccessToken() async throws -> String {
        current
    }

    func accessTokenAfterUnauthorized(rejectedToken: String) async throws -> String {
        rejectedTokens.append(rejectedToken)
        refreshCount += 1
        return current
    }
}

/// A clock that tests move by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.date = date
    }

    var now: Date { lock.withLock { date } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(seconds) }
    }
}

/// Records the waits the client asks for instead of sleeping.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []

    var sleeps: [TimeInterval] { lock.withLock { values } }

    func record(_ seconds: TimeInterval) {
        lock.withLock { values.append(seconds) }
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"),
                                "Missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    /// The reference `GET /me/player` example with the reference episode as its `item`.
    static func playbackWithEpisode() throws -> Data {
        var playback = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data("playback-state-reference")) as? [String: Any])
        let episode = try JSONSerialization.jsonObject(with: data("episode-reference"))
        playback["item"] = episode
        playback["currently_playing_type"] = "episode"
        return try JSONSerialization.data(withJSONObject: playback)
    }

    private final class BundleToken {}
}

extension HTTPURLResponse {
    static func stub(_ status: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.spotify.com")!, statusCode: status,
                        httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

func spotifyErrorJSON(status: Int, message: String, reason: String? = nil) -> Data {
    var error: [String: Any] = ["status": status, "message": message]
    if let reason { error["reason"] = reason }
    return try! JSONSerialization.data(withJSONObject: ["error": error])
}
