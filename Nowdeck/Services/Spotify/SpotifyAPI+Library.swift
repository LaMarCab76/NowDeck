import Foundation

// Library, search and "play this card" (milestone 5).
//
// Checked on developer.spotify.com on 2026-11-17 (references and the February 2026
// changelog, "Endpoints still available"):
// - `GET /me/playlists`: scope `playlist-read-private`; `limit` 1–50 (default 20), `offset`
//   up to 100 000. The item count moved from `tracks` to `items` (`tracks` is deprecated).
// - `GET /me/albums`, `GET /me/shows`, `GET /me/audiobooks`: scope `user-library-read`;
//   `limit` 1–50 (default 20). Albums and shows come wrapped in `{added_at, album|show}`,
//   audiobooks come unwrapped.
// - `GET /search`: `limit` 0–10 (default 5) since February 2026, `offset` 0–1000.
// - `PUT /me/player/play`: scope `user-modify-playback-state`, Premium only. "Valid
//   contexts are albums, artists & playlists": shows and audiobooks are not documented as
//   a `context_uri`, so the app does not send them.

extension SpotifyAPI {
    /// Items per library row. Spotify's guidelines allow at most 20 items per content row
    /// (docs/06-cumplimiento.md), and 20 is also the endpoints' default page size.
    static let libraryPageSize = 20

    /// `GET /me/playlists` (scope `playlist-read-private`; collaborative playlists also
    /// need `playlist-read-collaborative`, which the app requests).
    func savedPlaylists(limit: Int = SpotifyAPI.libraryPageSize,
                        offset: Int = 0) async throws -> Paging<SimplifiedPlaylist> {
        try await page(path: "/me/playlists", limit: limit, offset: offset)
    }

    /// `GET /me/albums` (scope `user-library-read`).
    ///
    /// No `market` is sent: with a user token, the account's country applies.
    func savedAlbums(limit: Int = SpotifyAPI.libraryPageSize,
                     offset: Int = 0) async throws -> Paging<SavedAlbum> {
        try await page(path: "/me/albums", limit: limit, offset: offset)
    }

    /// `GET /me/shows` (scope `user-library-read`).
    func savedShows(limit: Int = SpotifyAPI.libraryPageSize,
                    offset: Int = 0) async throws -> Paging<SavedShow> {
        try await page(path: "/me/shows", limit: limit, offset: offset)
    }

    /// `GET /me/audiobooks` (scope `user-library-read`). Audiobooks exist only in some
    /// markets (US, UK, Canada, Ireland, New Zealand and Australia, per the audiobook and
    /// search references); elsewhere this list is simply empty.
    func savedAudiobooks(limit: Int = SpotifyAPI.libraryPageSize,
                         offset: Int = 0) async throws -> Paging<SimplifiedAudiobook> {
        try await page(path: "/me/audiobooks", limit: limit, offset: offset)
    }

    /// `GET /search?q=…&type=…&limit=…&offset=…`. The reference lists no scope.
    func search(_ query: SearchQuery) async throws -> SearchResults {
        let request = Request(path: "/search", query: query.queryItems)
        let (data, _) = try await send(request)
        return try Self.decode(SearchResults.self, from: data)
    }

    /// `PUT /me/player/play` with `{"context_uri": …}` on the active device.
    ///
    /// No `device_id` is sent: "If not supplied, the user's currently active device is the
    /// target." Without an active device Spotify answers `404` (`SpotifyAPIError.notFound`;
    /// the reference does not list it, but it is how the player commands fail today), and a
    /// `403` covers the cases of `SpotifyAPIError.forbidden` (no Premium, among others).
    func playContext(uri: String) async throws {
        var request = Request(method: "PUT", path: "/me/player/play")
        request.body = try Self.playContextBody(uri: uri)
        _ = try await send(request)
    }

    /// The JSON body of `playContext(uri:)`. Separate so tests can check it.
    static func playContextBody(uri: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(PlayContextBody(contextUri: uri))
    }

    // MARK: Helpers

    private func page<Item>(path: String, limit: Int,
                            offset: Int) async throws -> Paging<Item> {
        let request = Request(path: path, query: [
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "offset", value: String(max(offset, 0))),
        ])
        let (data, _) = try await send(request)
        return try Self.decode(Paging<Item>.self, from: data)
    }
}

private struct PlayContextBody: Encodable {
    let contextUri: String

    private enum CodingKeys: String, CodingKey {
        case contextUri = "context_uri"
    }
}
