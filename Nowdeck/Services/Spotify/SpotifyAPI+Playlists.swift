import Foundation

// Adding the item that plays to one of the user's playlists (owner's request, 2026-11-18).
//
// Checked on developer.spotify.com on 2026-11-18 (docs/03-spotify-api.md, "Agregar a una
// playlist"):
// - `POST /playlists/{playlist_id}/items` is `[ADDED]` in the February 2026 changelog, which
//   also marks `POST /playlists/{id}/tracks` as `[REMOVED]` ("Use `POST /playlists/{id}/items`
//   instead"). The March, May and July 2026 changelogs do not touch it.
// - Body `{"uris": […], "position"?}`; "can be track or episode URIs"; "A maximum of 100
//   items can be added in one request"; without `position` the items are appended.
// - Scopes `playlist-modify-public` and `playlist-modify-private`. Documented answers: 201
//   (with `snapshot_id`), 401, 403, 429.
// - `GET /me/playlists` items carry `collaborative` ("`true` if the owner allows other users
//   to modify the playlist") and `owner.id`; those two say which playlists the user can edit.

extension SpotifyAPI {
    /// `POST /playlists/{id}/items` with one URI, appended at the end. Returns the new
    /// `snapshot_id` (empty if Spotify sends none).
    ///
    /// `send(_:)` does not retry it after a `5xx` or a network error: the write may have
    /// happened, and a retry could add the item twice. The one resend it makes is after a
    /// `401` with a refreshed token, which is safe: Spotify rejected the first one before
    /// doing anything.
    @discardableResult
    func addToPlaylist(playlistID: String, uri: String) async throws -> String {
        var request = Request(method: "POST",
                              path: "/playlists/\(Self.pathComponent(playlistID))/items")
        request.body = try Self.addItemsBody(uris: [uri])
        let (data, _) = try await send(request)
        return (try? Self.makeDecoder().decode(SnapshotAnswer.self, from: data))?.snapshotId ?? ""
    }

    /// The JSON body of `addToPlaylist`. Separate so tests can check it.
    static func addItemsBody(uris: [String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(AddItemsBody(uris: uris))
    }

    /// Every playlist of `GET /me/playlists`, page by page (50 per request, the maximum).
    ///
    /// Stops after `maximumPages` pages (2 500 playlists) so an endless `next` can never keep
    /// the sheet requesting; past that the list is cut. A page whose next offset does not
    /// move forward is a broken answer: it throws instead of looping on the same page.
    func allSavedPlaylists(maximumPages: Int = 50) async throws -> [SimplifiedPlaylist] {
        var playlists: [SimplifiedPlaylist] = []
        var offset: Int? = 0
        var pages = 0
        while let current = offset, pages < maximumPages {
            let page = try await savedPlaylists(limit: 50, offset: current)
            playlists += page.items
            if let next = page.nextOffset, next <= current {
                throw SpotifyAPIError.invalidResponse
            }
            offset = page.nextOffset
            pages += 1
        }
        return playlists
    }
}

private struct AddItemsBody: Encodable {
    let uris: [String]
}

private struct SnapshotAnswer: Decodable {
    let snapshotId: String?
}
