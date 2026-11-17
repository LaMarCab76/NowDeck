import Foundation

// Spotify Connect devices: the list and the playback transfer (milestone 4).
// Endpoints checked on developer.spotify.com on 2026-11-17 (docs/03-spotify-api.md).

extension SpotifyAPI {
    /// `GET /me/player/devices` (scope `user-read-playback-state`).
    ///
    /// The reference says that "some device models are not supported and will not be
    /// listed". In practice only devices with Spotify open (and speakers or TVs that are
    /// awake) show up, which is what the sheet's help explains. Device order is Spotify's;
    /// the sheet sorts it (`DeviceChoices`).
    func availableDevices() async throws -> [SpotifyDevice] {
        let (data, _) = try await send(Request(path: "/me/player/devices"))
        return try Self.decode(AvailableDevices.self, from: data).devices
    }

    /// `PUT /me/player` with `{"device_ids": ["<id>"], "play": <play>}` (scope
    /// `user-modify-playback-state`, Premium only).
    ///
    /// - `play: true` makes sure playback continues on the new device;
    /// - `play: false` keeps the current state (a paused track stays paused).
    ///
    /// Spotify accepts exactly one ID: an array with more answers `400`. The command is
    /// asynchronous on Spotify's side, so callers re-read the playback state a bit later
    /// instead of trusting the answer.
    func transferPlayback(to deviceID: String, play: Bool) async throws {
        let body = TransferPlaybackBody(deviceIds: [deviceID], play: play)
        let request = Request(method: "PUT", path: "/me/player",
                              body: try JSONEncoder().encode(body))
        _ = try await send(request)
    }
}

/// The body of `GET /me/player/devices`. A missing `devices` key counts as an empty list.
private struct AvailableDevices: Decodable {
    let devices: [SpotifyDevice]

    private enum CodingKeys: String, CodingKey {
        case devices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        devices = try container.decodeIfPresent([SpotifyDevice].self, forKey: .devices) ?? []
    }
}

/// The JSON body of the transfer. Keys are written out because the API client's encoder
/// does not convert to snake case.
struct TransferPlaybackBody: Encodable, Equatable {
    let deviceIds: [String]
    let play: Bool

    private enum CodingKeys: String, CodingKey {
        case deviceIds = "device_ids"
        case play
    }
}
