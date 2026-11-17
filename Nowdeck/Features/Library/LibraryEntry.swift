import Foundation

/// The filters of the library (`Biblioteca.dc.html`), in the mockup's order.
enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case playlists
    case albums
    case shows
    case audiobooks

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .playlists: return "Playlists"
        case .albums: return "Álbumes"
        case .shows: return "Podcasts"
        case .audiobooks: return "Audiolibros"
        }
    }
}

/// One card of a library row: what the view shows and what tapping it does.
///
/// Names come from Spotify and are kept verbatim (docs/06-cumplimiento.md). Only the type
/// prefix of the subtitle is localized.
struct LibraryEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case playlist
        case album
        case show
        case audiobook
    }

    var kind: Kind
    /// A valid `spotify:<kind>:<id>` URI. Items without one are dropped: they could not be
    /// played nor linked.
    var uri: String
    var name: String
    var subtitle: String
    var artworkURL: URL?
    /// The item's page on `open.spotify.com` (link back to Spotify).
    var pageURL: URL?
    /// The line under the name on the detail screen: "De <owner> · N temas" for playlists,
    /// "<artists> · <year>" for albums. `nil` falls back to `subtitle`.
    var detailSubtitle: String?

    var id: String { uri }

    /// Whether tapping the card starts playback here. `PUT /me/player/play` documents only
    /// albums, artists and playlists as a `context_uri`; podcasts and audiobooks open in
    /// Spotify instead (verified 2026-11-17).
    var playsInPlace: Bool {
        switch kind {
        case .playlist, .album: return true
        case .show, .audiobook: return false
        }
    }
}

extension LibraryEntry {
    /// Cards are 150 pt (450 px at 3×). Spotify sends 640, 300 and 64 px covers: take the
    /// smallest one of at least 300 px, which looks sharp enough and loads fast.
    static let preferredImageWidth = 300

    init?(playlist: SimplifiedPlaylist) {
        let subtitle: String
        switch playlist.itemCount {
        case 1?: subtitle = String(localized: "Playlist · 1 tema",
                                   comment: "Library card subtitle: a playlist with one track")
        case let count?: subtitle = String(localized: "Playlist · \(count) temas",
                                           comment: "Library card subtitle: number of tracks")
        case nil: subtitle = String(localized: "Playlist", comment: "Library card subtitle")
        }
        self.init(kind: .playlist, uri: playlist.uri, name: playlist.name, subtitle: subtitle,
                  images: playlist.images, externalURL: playlist.externalUrls?.spotify,
                  detailSubtitle: Self.playlistDetailSubtitle(
                      owner: playlist.owner?.displayName, count: playlist.itemCount))
    }

    init?(album: SimplifiedAlbum) {
        let artists = (album.artists ?? []).map(\.name).filter { !$0.isEmpty }
            .joined(separator: ", ")
        let subtitle = artists.isEmpty
            ? String(localized: "Álbum", comment: "Library card subtitle")
            : String(localized: "Álbum · \(artists)",
                     comment: "Library card subtitle: the album's artists, verbatim")
        let detail = [artists, album.releaseYear ?? ""].filter { !$0.isEmpty }
            .joined(separator: " · ")
        self.init(kind: .album, uri: album.uri, name: album.name, subtitle: subtitle,
                  images: album.images, externalURL: album.externalUrls?.spotify,
                  detailSubtitle: detail.isEmpty ? nil : detail)
    }

    /// The show's `publisher` was removed in February 2026, so the subtitle shows the
    /// number of episodes instead of the mockup's "Podcast · <publisher>".
    init?(show: SimplifiedShow) {
        let subtitle: String
        switch show.totalEpisodes {
        case 1?: subtitle = String(localized: "Podcast · 1 episodio",
                                   comment: "Library card subtitle: a podcast with one episode")
        case let count? where count > 0:
            subtitle = String(localized: "Podcast · \(count) episodios",
                              comment: "Library card subtitle: number of episodes")
        default: subtitle = String(localized: "Podcast", comment: "Library card subtitle")
        }
        self.init(kind: .show, uri: show.uri, name: show.name, subtitle: subtitle,
                  images: show.images, externalURL: show.externalUrls?.spotify)
    }

    init?(audiobook: SimplifiedAudiobook) {
        let authors = (audiobook.authors ?? []).compactMap(\.name).filter { !$0.isEmpty }
            .joined(separator: ", ")
        let subtitle = authors.isEmpty
            ? String(localized: "Audiolibro", comment: "Library card subtitle")
            : String(localized: "Audiolibro · \(authors)",
                     comment: "Library card subtitle: the audiobook's authors, verbatim")
        self.init(kind: .audiobook, uri: audiobook.uri, name: audiobook.name,
                  subtitle: subtitle, images: audiobook.images,
                  externalURL: audiobook.externalUrls?.spotify)
    }

    private init?(kind: Kind, uri: String?, name: String?, subtitle: String,
                  images: [SpotifyImage]?, externalURL: String?, detailSubtitle: String? = nil) {
        guard let uri, SpotifyURI(uri) != nil else { return nil }
        self.init(kind: kind, uri: uri, name: name ?? "", subtitle: subtitle,
                  artworkURL: Self.artworkURL(images ?? []),
                  pageURL: NowPlaying.pageURL(externalURL: externalURL, uri: uri),
                  detailSubtitle: detailSubtitle)
    }

    /// "De Lucía · 48 temas", or the parts that are known. The owner's name comes from
    /// Spotify and is kept verbatim.
    private static func playlistDetailSubtitle(owner: String?, count: Int?) -> String? {
        var parts: [String] = []
        if let owner, !owner.isEmpty {
            parts.append(String(localized: "De \(owner)",
                                comment: "Playlist detail: the playlist's owner, verbatim"))
        }
        switch count {
        case 1?: parts.append(String(localized: "1 tema",
                                     comment: "Playlist detail: a playlist with one track"))
        case let count?: parts.append(String(localized: "\(count) temas",
                                             comment: "Playlist detail: number of tracks"))
        case nil: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The smallest image at least `preferredImageWidth` wide, or the largest one when all
    /// are smaller. Images without a width (Spotify sends `null` for some playlist mosaics)
    /// count as large enough. Only `https` URLs are used.
    static func artworkURL(_ images: [SpotifyImage]) -> URL? {
        let usable = images.filter { URL(string: $0.url)?.scheme == "https" }
        let bigEnough = usable.filter { ($0.width ?? Int.max) >= preferredImageWidth }
        let chosen = bigEnough.min { ($0.width ?? Int.max) < ($1.width ?? Int.max) }
            ?? usable.max { ($0.width ?? 0) < ($1.width ?? 0) }
        return chosen.flatMap { URL(string: $0.url) }
    }
}
