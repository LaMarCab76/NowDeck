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
// endpoint to remove, reorder or jump to an item, so the queue sheet is read-only.

extension SpotifyAPI {
    /// `GET /me/player/queue`.
    func playbackQueue() async throws -> PlaybackQueue {
        let (data, _) = try await send(Request(path: "/me/player/queue"))
        return try Self.decode(PlaybackQueue.self, from: data)
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
