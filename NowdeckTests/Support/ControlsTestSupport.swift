import Foundation
import XCTest
@testable import Nowdeck

/// Builds `GET /me/player` answers from the hand-made fixture, changing only what a test
/// cares about.
struct PlaybackJSON {
    var isPlaying = true
    var shuffle = false
    var repeatState = "off"
    /// `nil` sends `progress_ms: null`, which Spotify allows.
    var progressMs: Int? = 84_000
    /// Actions inside `actions.disallows` (snake_case keys), all set to `true`.
    var disallows: [String] = []
    var deviceID = "device-1"
    var volume: Int? = 50
    var supportsVolume = true
    var isRestricted = false
    /// Replace the track with the reference podcast episode.
    var episode = false

    func data() throws -> Data {
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Fixture.data("playback-state-playing"))
                as? [String: Any])
        object["is_playing"] = isPlaying
        object["shuffle_state"] = shuffle
        object["repeat_state"] = repeatState
        object["progress_ms"] = progressMs ?? NSNull()
        object["actions"] = ["disallows": Dictionary(uniqueKeysWithValues: disallows.map { ($0, true) })]
        var device = try XCTUnwrap(object["device"] as? [String: Any])
        device["id"] = deviceID
        device["volume_percent"] = volume ?? NSNull()
        device["supports_volume"] = supportsVolume
        device["is_restricted"] = isRestricted
        object["device"] = device
        if episode {
            object["item"] = try JSONSerialization.jsonObject(with: Fixture.data("episode-reference"))
            object["currently_playing_type"] = "episode"
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    func state() throws -> PlaybackState {
        try SpotifyAPI.makeDecoder().decode(PlaybackState.self, from: data())
    }
}

/// Thread-safe values that a stub handler reads while the test changes them.
final class StubBox<Value>: @unchecked Sendable {
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

extension URLRequest {
    /// `PUT /v1/me/player/pause` → `"PUT /me/player/pause"`, for readable assertions.
    var commandLine: String {
        let path = url?.path.replacingOccurrences(of: "/v1", with: "", options: .anchored) ?? ""
        return "\(httpMethod ?? "") \(path)"
    }

    func queryValue(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }
}

extension XCTestCase {
    /// Polls `condition` on the main actor until it holds or `timeout` passes.
    @MainActor
    func eventually(timeout: TimeInterval = 2, _ message: String = "Timed out",
                    _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail(message) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
