import Foundation

// Playback commands (milestone 3). Every endpoint here was checked on developer.spotify.com
// on 2026-11-17:
// - scope `user-modify-playback-state` (already requested, `SpotifyAuthorization`);
// - "This API only works for users who have Spotify Premium";
// - documented answers: 204 on success, 401, 403, 429;
// - all of them are in the "Endpoints still available" list (Player) of the February 2026
//   changelog, the one that applies to Development Mode apps.
//
// `device_id` is optional on all of them ("If not supplied, the user's currently active
// device is the target"). The app always controls the active device, so it is not sent.
//
// Commands are never retried automatically (see `SpotifyAPI.send(_:)`): repeating "next"
// could skip two tracks.

/// A command for the active Spotify Connect device.
enum PlaybackCommand: Equatable, Sendable {
    /// `PUT /me/player/play` without a body: resumes the current context.
    case play
    /// `PUT /me/player/pause`.
    case pause
    /// `POST /me/player/next`.
    case next
    /// `POST /me/player/previous`.
    case previous
    /// `PUT /me/player/shuffle?state=true|false`.
    case shuffle(Bool)
    /// `PUT /me/player/repeat?state=off|context|track`.
    case repeatMode(RepeatMode)
    /// `PUT /me/player/volume?volume_percent=0…100`. Values outside the range are clamped.
    case volume(Int)
    /// `PUT /me/player/seek?position_ms=…`. Used for the ±15 s buttons of podcast episodes.
    /// Negative values are sent as 0. "Passing in a position that is greater than the length
    /// of the track will cause the player to start playing the next song", so callers clamp
    /// to the duration.
    case seek(positionMs: Int)

    var request: SpotifyAPI.Request {
        switch self {
        case .play:
            return SpotifyAPI.Request(method: "PUT", path: "/me/player/play")
        case .pause:
            return SpotifyAPI.Request(method: "PUT", path: "/me/player/pause")
        case .next:
            return SpotifyAPI.Request(method: "POST", path: "/me/player/next")
        case .previous:
            return SpotifyAPI.Request(method: "POST", path: "/me/player/previous")
        case .shuffle(let isOn):
            return SpotifyAPI.Request(method: "PUT", path: "/me/player/shuffle",
                                      query: [URLQueryItem(name: "state",
                                                           value: isOn ? "true" : "false")])
        case .repeatMode(let mode):
            return SpotifyAPI.Request(method: "PUT", path: "/me/player/repeat",
                                      query: [URLQueryItem(name: "state", value: mode.rawValue)])
        case .volume(let percent):
            let clamped = min(100, max(0, percent))
            return SpotifyAPI.Request(method: "PUT", path: "/me/player/volume",
                                      query: [URLQueryItem(name: "volume_percent",
                                                           value: String(clamped))])
        case .seek(let positionMs):
            return SpotifyAPI.Request(method: "PUT", path: "/me/player/seek",
                                      query: [URLQueryItem(name: "position_ms",
                                                           value: String(max(0, positionMs)))])
        }
    }
}

extension SpotifyAPI {
    /// Sends a playback command. Throws `SpotifyAPIError` (for example `.notFound` when there
    /// is no active device, `.forbidden` without Premium) or `AuthError`.
    func sendCommand(_ command: PlaybackCommand) async throws {
        _ = try await send(command.request)
    }
}
