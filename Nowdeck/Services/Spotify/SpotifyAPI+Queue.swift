import Foundation

// The playback queue. Checked on developer.spotify.com on 2026-11-17
// (docs/03-spotify-api.md, "Cola"):
// - `GET /me/player/queue` is in the "Endpoints still available" list (Player) of the
//   February 2026 changelog; the May and July 2026 changelogs do not touch it;
// - scopes `user-read-currently-playing` and `user-read-playback-state`, both already
//   requested (`SpotifyAuthorization`);
// - documented answers: 200, 401, 403, 429. The reference states no maximum for `queue`.
//
// The Web API only reads the queue and adds to it (`POST /me/player/queue`). There is no
// endpoint to remove, reorder or jump to an item. Tapping a row plays that track with
// `PUT /me/player/play` instead (`playFromQueue`), checked again on 2026-11-18: still in
// "Endpoints still available" (Player) of the February 2026 changelog, no deprecation note,
// scope `user-modify-playback-state`, Premium only, 204/401/403/429. The reference says
// `offset` is "Only available when context_uri corresponds to an album or playlist object"
// and documents `offset.uri` ("the uri of the item to start at"). It does not say what
// happens when that uri is not part of the context.

extension SpotifyAPI {
    /// `GET /me/player/queue`.
    func playbackQueue() async throws -> PlaybackQueue {
        let (data, _) = try await send(Request(path: "/me/player/queue"))
        return try Self.decode(PlaybackQueue.self, from: data)
    }

    /// Plays a track from the queue on the active device.
    ///
    /// With an album or playlist context, it first asks for the context starting at that
    /// track (`context_uri` + `offset.uri`), so the rest of the playlist or album still
    /// follows it. The queue mixes context tracks with tracks added by hand, without telling
    /// them apart; if Spotify rejects the offset (`400` or `404`), the track plays on its own
    /// (`uris`), like it does without a usable context. A `404` from that second request
    /// means there is no active device.
    func playFromQueue(trackURI: String, context: PlaybackContext?) async throws {
        if let contextURI = PlayFromQueueBody.offsetContextURI(context) {
            do {
                try await play(.init(contextUri: contextURI, offset: .init(uri: trackURI)))
                return
            } catch SpotifyAPIError.notFound, SpotifyAPIError.http(status: 400, _) {
                // Not in the context (or no device): try the track alone.
            }
        }
        try await play(.init(uris: [trackURI]))
    }

    private func play(_ body: PlayFromQueueBody) async throws {
        var request = Request(method: "PUT", path: "/me/player/play")
        request.body = try body.encoded()
        _ = try await send(request)
    }
}

/// The JSON body of `playFromQueue`: either a context with an offset or a list of tracks.
struct PlayFromQueueBody: Encodable, Equatable {
    struct Offset: Encodable, Equatable {
        var uri: String
    }

    var contextUri: String?
    var offset: Offset?
    var uris: [String]?

    private enum CodingKeys: String, CodingKey {
        case contextUri = "context_uri", offset, uris
    }

    /// The context to start inside, or `nil`: `offset` is documented only for albums and
    /// playlists (not artists, shows or the saved tracks collection).
    static func offsetContextURI(_ context: PlaybackContext?) -> String? {
        guard let context, ["album", "playlist"].contains(context.type),
              !context.uri.isEmpty else { return nil }
        return context.uri
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }
}

/// The body of `GET /me/player/queue`.
///
/// The reference describes `queue` as "The tracks or episodes in the queue. Can be empty."
/// It mixes what the user queued by hand and what follows in the context, without telling
/// them apart.
struct PlaybackQueue: Decodable, Equatable, Sendable {
    /// "The currently playing track or episode. Can be `null`."
    var currentlyPlaying: PlaybackItem?
    var queue: [PlaybackItem]

    init(currentlyPlaying: PlaybackItem? = nil, queue: [PlaybackItem] = []) {
        self.currentlyPlaying = currentlyPlaying
        self.queue = queue
    }

    private enum CodingKeys: String, CodingKey {
        case currentlyPlaying, queue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentlyPlaying = try container.decodeIfPresent(PlaybackItem.self,
                                                         forKey: .currentlyPlaying)
        // A missing or `null` list counts as an empty queue.
        queue = try container.decodeIfPresent([PlaybackItem].self, forKey: .queue) ?? []
    }
}
