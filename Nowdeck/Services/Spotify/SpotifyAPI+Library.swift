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
// - `GET /albums/{id}/tracks`: in "Endpoints still available" (Metadata); `limit` 1–50
//   (default 20), `offset`. Simplified tracks carry `artists`, `duration_ms`, `explicit`,
//   `is_local`, `restrictions` and, only with Track Relinking, `is_playable`.
// - `GET /playlists/{id}/items`: added in February 2026 (it replaces `/tracks`, removed).
//   Scope `playlist-read-private`; `limit` 1–50 (default 20). "This endpoint is only
//   accessible for playlists owned by the current user or playlists the user is a
//   collaborator of. A 403 Forbidden status code will be returned if the user is neither
//   the owner nor a collaborator of the playlist."
//
// `market` is not sent on the track lists: the references document only country codes
// (`from_token` is not mentioned) and say the account's country "will take priority over
// this parameter".

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

    /// Tracks per page of the detail screen: the maximum of both endpoints, so an album
    /// usually takes a single request.
    static let collectionPageSize = 50

    /// `GET /albums/{id}/tracks`.
    func albumTracks(albumID: String, limit: Int = SpotifyAPI.collectionPageSize,
                     offset: Int = 0) async throws -> Paging<CollectionItem> {
        try await page(path: "/albums/\(Self.pathComponent(albumID))/tracks",
                       limit: limit, offset: offset)
    }

    /// `GET /playlists/{id}/items?additional_types=track,episode`. Throws
    /// `SpotifyAPIError.forbidden` for playlists the user neither owns nor collaborates on.
    ///
    /// `additional_types` ("item types that your client supports besides the default track
    /// type") includes `episode`, since the screen can show episodes. No `fields` filter: the field
    /// names changed in February 2026 (`track` → `item`) and a filter with the wrong name
    /// would silently return empty items.
    func playlistItems(playlistID: String, limit: Int = SpotifyAPI.collectionPageSize,
                       offset: Int = 0) async throws -> Paging<PlaylistItem> {
        try await page(path: "/playlists/\(Self.pathComponent(playlistID))/items",
                       limit: limit, offset: offset,
                       extraQuery: [URLQueryItem(name: "additional_types", value: "track,episode")])
    }

    /// `GET /search?q=…&type=…&limit=…&offset=…`. The reference lists no scope.
    func search(_ query: SearchQuery) async throws -> SearchResults {
        let request = Request(path: "/search", query: query.queryItems)
        let (data, _) = try await send(request)
        return try Self.decode(SearchResults.self, from: data)
    }

    /// `PUT /me/player/play` on the active device. An optional zero-based position
    /// starts the chosen occurrence within an album or playlist.
    ///
    /// No `device_id` is sent: "If not supplied, the user's currently active device is the
    /// target." Without an active device Spotify answers `404` (`SpotifyAPIError.notFound`;
    /// the reference does not list it, but it is how the player commands fail today), and a
    /// `403` covers the cases of `SpotifyAPIError.forbidden` (no Premium, among others).
    func playContext(uri: String, position: Int? = nil) async throws {
        var request = Request(method: "PUT", path: "/me/player/play")
        request.body = try Self.playContextBody(uri: uri, position: position)
        _ = try await send(request)
    }

    /// The JSON body of `playContext`. Whole collections omit the offset.
    static func playContextBody(uri: String, position: Int? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(PlayContextBody(contextUri: uri,
                                                  offset: position.map(PlayContextBody.Offset.init)))
    }

    // MARK: Helpers

    private func page<Item>(path: String, limit: Int, offset: Int,
                            extraQuery: [URLQueryItem] = []) async throws -> Paging<Item> {
        let request = Request(path: path, query: [
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "offset", value: String(max(offset, 0))),
        ] + extraQuery)
        let (data, _) = try await send(request)
        return try Self.decode(Paging<Item>.self, from: data)
    }
}

private struct PlayContextBody: Encodable {
    struct Offset: Encodable {
        let position: Int
    }

    let contextUri: String
    let offset: Offset?

    private enum CodingKeys: String, CodingKey {
        case contextUri = "context_uri"
        case offset
    }
}
