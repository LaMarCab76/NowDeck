import Foundation

/// What the player shows for the current item, derived from `PlaybackState`.
struct NowPlaying: Equatable {
    var title: String
    /// Artists (tracks) or the podcast name (episodes).
    var subtitle: String
    var isExplicit: Bool
    var durationMs: Int
    var artworkURL: URL?
    /// Key for the artwork color cache: the album ID for tracks.
    var artworkCacheKey: String?
    /// The item's page on Spotify (link back from the logo).
    var itemURL: URL?
    /// The first artist with an ID (tracks only), for the background photo
    /// (`GET /artists/{id}`).
    var artistID: String?
    var isAd: Bool = false

    /// `nil` when there is nothing to show: no item, or an item type the app doesn't know.
    init?(state: PlaybackState) {
        switch state.item {
        case .track(let track):
            title = track.name
            subtitle = track.artists.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
            isExplicit = track.explicit
            durationMs = track.durationMs
            artworkURL = Self.bestImage(track.album?.images ?? [])
            artworkCacheKey = track.album?.id
            itemURL = Self.pageURL(externalURL: track.externalUrls?.spotify, uri: track.uri)
            artistID = track.artists.lazy.compactMap(\.id).first { !$0.isEmpty }

        case .episode(let episode):
            title = episode.name
            subtitle = episode.show?.name ?? ""
            isExplicit = episode.explicit
            durationMs = episode.durationMs
            artworkURL = Self.bestImage(episode.images.isEmpty ? (episode.show?.images ?? [])
                                                                : episode.images)
            artworkCacheKey = nil
            itemURL = Self.pageURL(externalURL: episode.externalUrls?.spotify, uri: episode.uri)

        case nil where state.currentlyPlayingType == "ad":
            // During ads `item` is null. Keep the player on screen instead of jumping to
            // "Nada sonando" for thirty seconds.
            title = String(localized: "Publicidad",
                           comment: "Player title while Spotify plays an ad")
            subtitle = ""
            isExplicit = false
            durationMs = 0
            artworkURL = nil
            artworkCacheKey = nil
            itemURL = nil
            isAd = true

        case nil, .unsupported:
            return nil
        }
    }

    /// The largest image: Spotify sends 640, 300 and 64 px, and the player shows 256 pt
    /// (768 px on a 3× screen).
    static func bestImage(_ images: [SpotifyImage]) -> URL? {
        let best = images.max { ($0.width ?? 0) < ($1.width ?? 0) } ?? images.first
        guard let string = best?.url, let url = URL(string: string), url.scheme == "https" else {
            return nil
        }
        return url
    }

    static func pageURL(externalURL: String?, uri: String?) -> URL? {
        if let externalURL, let url = URL(string: externalURL), url.host == "open.spotify.com" {
            return url
        }
        return uri.flatMap(SpotifyURI.init)?.webURL
    }
}

/// Where the item plays from ("Desde la playlist …").
struct PlaybackOrigin: Equatable {
    enum Kind: Equatable {
        case playlist
        case album
        case artist
        case show
        /// The user's saved tracks ("Tus me gusta").
        case likedSongs
    }

    var kind: Kind
    /// `nil` while unknown: the player then shows only the type ("Desde una playlist").
    var name: String?
    var url: URL?
    /// Set for playlists: the name has to be fetched with `GET /playlists/{id}`.
    var playlistID: String?

    /// Builds the origin from the context. Album, artist and show names come from the item
    /// itself when it belongs to the context, so they cost no extra request. Unknown context
    /// types give `nil` (no origin line).
    static func from(context: PlaybackContext?, item: PlaybackItem?) -> PlaybackOrigin? {
        guard let context else { return nil }
        let uri = SpotifyURI(context.uri)
        let url = NowPlaying.pageURL(externalURL: context.externalUrls?.spotify, uri: context.uri)

        switch context.type {
        case "playlist":
            return PlaybackOrigin(kind: .playlist, name: nil, url: url, playlistID: uri?.id)

        case "album":
            var name: String?
            if case .track(let track) = item, let album = track.album, album.uri == context.uri,
               !album.name.isEmpty {
                name = album.name
            }
            return PlaybackOrigin(kind: .album, name: name, url: url)

        case "artist":
            var name: String?
            if case .track(let track) = item {
                name = track.artists.first { $0.uri == context.uri }?.name
            }
            return PlaybackOrigin(kind: .artist, name: name, url: url)

        case "show":
            var name: String?
            if case .episode(let episode) = item, let show = episode.show,
               show.uri == context.uri, !show.name.isEmpty {
                name = show.name
            }
            return PlaybackOrigin(kind: .show, name: name, url: url)

        case "collection":
            return PlaybackOrigin(kind: .likedSongs, name: nil,
                                  url: URL(string: "https://open.spotify.com/collection/tracks"))

        default:
            return nil
        }
    }
}
