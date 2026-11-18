import Foundation

// Recently played tracks. Checked on developer.spotify.com on 2026-11-18
// (docs/03-spotify-api.md, "Último tema escuchado"):
// - `GET /me/player/recently-played` is in the "Endpoints still available" list (Player) of
//   the February 2026 changelog; the Development Mode migration guide does not restrict it;
// - scope `user-read-recently-played` (requested since 2026-11-18, `SpotifyAuthorization`);
// - `limit` 1–50 (default 20); items are `{track, played_at, context}`; "Currently doesn't
//   support podcast episodes";
// - documented answers: 200, 401, 403, 429.
//
// Only Ajustes uses it, for the sample photo of the background preview when nothing plays.
// Sessions started before the scope was added answer `403`: the caller then falls back to
// what the app saw playing.

extension SpotifyAPI {
    /// `GET /me/player/recently-played?limit=…`, newest first. Items without a track are
    /// dropped.
    func recentlyPlayedTracks(limit: Int = 1) async throws -> [PlaybackItem] {
        let request = Request(path: "/me/player/recently-played",
                              query: [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))])
        let (data, _) = try await send(request)
        return try Self.decode(RecentlyPlayed.self, from: data).items.compactMap(\.track)
    }
}

/// The body of `GET /me/player/recently-played`, only what the app reads.
struct RecentlyPlayed: Decodable, Equatable, Sendable {
    struct Item: Decodable, Equatable, Sendable {
        /// "The track the user listened to." `nil` if missing.
        var track: PlaybackItem?
    }

    var items: [Item]

    private enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
    }
}
