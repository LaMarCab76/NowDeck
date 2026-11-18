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
//
// Which playlists already hold the item (owner's request, 2026-11-18). Checked on
// developer.spotify.com on 2026-11-18:
// - No endpoint answers "which playlists contain this track": each editable playlist is read
//   with `GET /playlists/{id}/items` (`limit` 1–50). "This endpoint is only accessible for
//   playlists owned by the current user or playlists the user is a collaborator of", which
//   are exactly the ones the sheet lists.
// - `GET /me/playlists` items carry `snapshot_id`, "The version identifier for the current
//   playlist": a playlist is read again only when it changes.
// - `fields` exists, but its examples still say `track` while the schema says `item`; a
//   filter with the wrong name would return empty items, so it is not used (same choice as
//   the detail screen).

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

extension SpotifyAPI {
    /// The URI of every item of a playlist the user can edit, page by page (50 per request,
    /// the maximum). Stops after `maximumPages` pages (10 000 items, Spotify's limit for a
    /// playlist); a page whose next offset does not move forward throws.
    func playlistItemURIs(playlistID: String, maximumPages: Int = 200) async throws -> Set<String> {
        var uris = Set<String>()
        var offset: Int? = 0
        var pages = 0
        while let current = offset, pages < maximumPages {
            let page = try await playlistItems(playlistID: playlistID, limit: 50, offset: current)
            for entry in page.items {
                if let uri = entry.content?.uri, !uri.isEmpty { uris.insert(uri) }
            }
            if let next = page.nextOffset, next <= current {
                throw SpotifyAPIError.invalidResponse
            }
            offset = page.nextOffset
            pages += 1
        }
        return uris
    }
}

private struct AddItemsBody: Encodable {
    let uris: [String]
}

private struct SnapshotAnswer: Decodable {
    let snapshotId: String?
}
