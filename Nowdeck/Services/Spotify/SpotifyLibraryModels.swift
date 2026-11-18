import Foundation

// Models of the library and search answers (milestone 5). Decoded with `convertFromSnakeCase`
// (`SpotifyAPI.makeDecoder()`).
//
// Fields follow the references of "Get Current User's Playlists", "Get User's Saved
// Albums", "Get User's Saved Shows", "Get User's Saved Audiobooks" and "Search for Item"
// (checked 2026-11-17). Fields removed in Development Mode by the February 2026 changes
// (`available_markets`, `popularity`, `label`, the show and audiobook `publisher`) are not
// decoded, even though the reference examples still show them.
//
// Almost every field is optional: the views decide what to show when something is
// missing (`LibraryEntry`), so one odd item never breaks a whole page.

/// Spotify's paging object: `href`, `limit`, `next`, `offset`, `previous`, `total`, `items`.
///
/// `items` is read leniently: `null` entries and entries that fail to decode are dropped
/// instead of failing the whole page. Spotify documents `null` entries in playlist
/// contents, and an unreadable item should cost one card, not the row.
struct Paging<Item: Decodable & Sendable>: Decodable, Sendable {
    var items: [Item]
    var limit: Int?
    var offset: Int?
    var total: Int?
    /// URL of the next page, `nil` on the last one.
    var next: String?

    init(items: [Item], limit: Int? = nil, offset: Int? = nil, total: Int? = nil,
         next: String? = nil) {
        self.items = items
        self.limit = limit
        self.offset = offset
        self.total = total
        self.next = next
    }

    private enum CodingKeys: String, CodingKey {
        case items, limit, offset, total, next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lenient = try container.decodeIfPresent([Lenient<Item>].self, forKey: .items) ?? []
        items = lenient.compactMap(\.value)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        next = try container.decodeIfPresent(String.self, forKey: .next)
    }

    /// Where the next page starts, or `nil` when this is the last page.
    ///
    /// Counts the raw page size (`limit`), not the decoded items: dropped `null` entries
    /// still take a position on Spotify's side.
    var nextOffset: Int? {
        guard next != nil else { return nil }
        let (nextOffset, overflow) = (offset ?? 0).addingReportingOverflow(limit ?? items.count)
        return overflow ? nil : nextOffset
    }
}

/// One array element that may be `null` or malformed.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = container.decodeNil() ? nil : try? container.decode(Value.self)
    }
}

/// `{href, total}`: how many items a playlist has.
struct ItemCount: Decodable, Equatable, Sendable {
    var total: Int?
}

/// A playlist in `GET /me/playlists` and in search results (`SimplifiedPlaylistObject`).
struct SimplifiedPlaylist: Decodable, Equatable, Sendable {
    struct Owner: Decodable, Equatable, Sendable {
        var id: String?
        var displayName: String?
    }

    var id: String?
    var name: String?
    var uri: String?
    /// Can be `null` or empty (playlists without a cover).
    var images: [SpotifyImage]?
    var owner: Owner?
    /// "`true` if the owner allows other users to modify the playlist": the user can add to
    /// it even when someone else owns it (Agregar a una playlist).
    var collaborative: Bool?
    /// The count since February 2026 ("tracks → items").
    var items: ItemCount?
    /// The old name of `items`, still in the reference as deprecated.
    var tracks: ItemCount?
    var externalUrls: ExternalURLs?

    /// Number of items, from `items` or, on older answers, `tracks`.
    var itemCount: Int? { items?.total ?? tracks?.total }
}

/// An album in `GET /me/albums` (inside `SavedAlbum`) and in search results.
struct SimplifiedAlbum: Decodable, Equatable, Sendable {
    var id: String?
    /// "In case of an album takedown, the value may be an empty string."
    var name: String?
    var uri: String?
    /// `album`, `single` or `compilation`.
    var albumType: String?
    var totalTracks: Int?
    /// `"1981-12-15"`, `"1981-12"` or `"1981"`, depending on `release_date_precision`.
    var releaseDate: String?
    var images: [SpotifyImage]?
    var artists: [ArtistSummary]?
    var externalUrls: ExternalURLs?

    /// The year of `releaseDate`, the only part the detail screen shows.
    var releaseYear: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        let year = releaseDate.prefix(4)
        return year.allSatisfy(\.isNumber) ? String(year) : nil
    }
}

/// An item of `GET /me/albums`: `{added_at, album}`.
struct SavedAlbum: Decodable, Equatable, Sendable {
    var album: SimplifiedAlbum
}

/// A podcast in `GET /me/shows` (inside `SavedShow`) and in search results. `publisher`
/// was removed in February 2026.
struct SimplifiedShow: Decodable, Equatable, Sendable {
    var id: String?
    var name: String?
    var uri: String?
    var images: [SpotifyImage]?
    var totalEpisodes: Int?
    var externalUrls: ExternalURLs?
}

/// An item of `GET /me/shows`: `{added_at, show}`.
struct SavedShow: Decodable, Equatable, Sendable {
    var show: SimplifiedShow
}

/// An audiobook. `GET /me/audiobooks` returns these directly, without an `added_at`
/// wrapper. `publisher` was removed in February 2026.
struct SimplifiedAudiobook: Decodable, Equatable, Sendable {
    struct Person: Decodable, Equatable, Sendable {
        var name: String?
    }

    var id: String?
    var name: String?
    var uri: String?
    var images: [SpotifyImage]?
    var authors: [Person]?
    var narrators: [Person]?
    var totalChapters: Int?
    var externalUrls: ExternalURLs?
}

/// A track of `GET /albums/{id}/tracks` (`SimplifiedTrackObject`), or the track or episode
/// inside a playlist item (`TrackObject` / `EpisodeObject`). One type for the three, since
/// the detail screen shows the same things for all of them.
struct CollectionItem: Decodable, Equatable, Sendable {
    /// Any object with a `name`. Unlike `ArtistSummary`, a missing name does not drop the
    /// whole track.
    struct Named: Decodable, Equatable, Sendable {
        var name: String?
    }

    /// `track` or `episode`.
    var type: String?
    var name: String?
    var uri: String?
    var durationMs: Int?
    var explicit: Bool?
    /// "Part of the response when Track Relinking is applied" (only with `market`, which the
    /// app does not send), so it is usually absent.
    var isPlayable: Bool?
    /// "Included in the response when a content restriction is applied" (`market`,
    /// `product`, `explicit`, and maybe others in the future).
    var restrictions: Restrictions?
    var isLocal: Bool?
    /// Tracks.
    var artists: [Named]?
    /// Episodes.
    var show: Named?
    var externalUrls: ExternalURLs?

    struct Restrictions: Decodable, Equatable, Sendable {
        var reason: String?
    }
}

/// An item of `GET /playlists/{id}/items`: `{added_at, added_by, is_local, item}`.
///
/// Since February 2026 the content is in `item`; `track` holds the same thing and is
/// marked "Deprecated: Use `item` instead" (checked 2026-11-17). Both are read.
struct PlaylistItem: Decodable, Equatable, Sendable {
    var isLocal: Bool?
    var item: CollectionItem?
    var track: CollectionItem?

    var content: CollectionItem? { item ?? track }
}

/// `GET /search`. Only the types the app asks for are read; each one is a paging object
/// and is `nil` when that type was not requested.
struct SearchResults: Decodable, Sendable {
    var tracks: Paging<SpotifyTrack>?
    var albums: Paging<SimplifiedAlbum>?
    var playlists: Paging<SimplifiedPlaylist>?
    var shows: Paging<SimplifiedShow>?
    var audiobooks: Paging<SimplifiedAudiobook>?
}

/// The item types of `GET /search` that the app uses. The reference also allows `artist`
/// and `episode`; the docs of Nowdeck only ask for these five.
enum SearchType: String, CaseIterable, Sendable {
    case track
    case album
    case playlist
    case show
    case audiobook
}

/// A search request, with the limits of the reference applied.
struct SearchQuery: Equatable, Sendable {
    /// Maximum `limit` since February 2026 (it was 50). The default is now 5.
    static let maximumLimit = 10
    /// The reference allows offsets from 0 to 1000.
    static let maximumOffset = 1000

    var text: String
    var types: [SearchType]
    var limit: Int
    var offset: Int

    /// `nil` when the text is empty after trimming spaces: Spotify requires `q`.
    init?(text: String, types: [SearchType] = SearchType.allCases,
          limit: Int = SearchQuery.maximumLimit, offset: Int = 0) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !types.isEmpty else { return nil }
        self.text = trimmed
        self.types = types
        self.limit = min(max(limit, 1), Self.maximumLimit)
        self.offset = min(max(offset, 0), Self.maximumOffset)
    }

    /// `q`, `type` (comma-separated), `limit` and `offset`. `URLComponents` encodes them;
    /// `SpotifyAPI` additionally encodes `+`, which would otherwise arrive as a space.
    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "type", value: types.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
    }
}
