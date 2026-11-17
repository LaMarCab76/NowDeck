import Foundation

// Models of the Web API answers the app reads. Decoded with `convertFromSnakeCase`
// (`SpotifyAPI.makeDecoder()`), so property names are the camelCase form of the JSON keys.
//
// Fields follow the "Get Playback State" reference (verified 2026-11-17). Only what the app
// uses is decoded; deprecated or removed fields (`popularity`, `available_markets`,
// `linked_from`, `preview_url`, the show's `publisher`) are left out on purpose. Most fields
// are optional so that one missing value does not break the whole player.

/// `GET /me/player`.
struct PlaybackState: Decodable, Equatable, Sendable {
    var device: SpotifyDevice?
    var repeatState: RepeatMode
    var shuffleState: Bool
    /// `nil` when playing something without a context (for example, a single track).
    var context: PlaybackContext?
    /// When the playback state last changed (Spotify's clock, Unix ms). Not used for the
    /// progress interpolation: that uses the local time the answer arrived.
    var timestamp: Int64?
    var progressMs: Int?
    var isPlaying: Bool
    /// `nil` during ads and for some local content.
    var item: PlaybackItem?
    /// `track`, `episode`, `ad` or `unknown`.
    var currentlyPlayingType: String?
    var actions: PlaybackActions

    init(
        device: SpotifyDevice? = nil,
        repeatState: RepeatMode = .off,
        shuffleState: Bool = false,
        context: PlaybackContext? = nil,
        timestamp: Int64? = nil,
        progressMs: Int? = nil,
        isPlaying: Bool = false,
        item: PlaybackItem? = nil,
        currentlyPlayingType: String? = nil,
        actions: PlaybackActions = PlaybackActions()
    ) {
        self.device = device
        self.repeatState = repeatState
        self.shuffleState = shuffleState
        self.context = context
        self.timestamp = timestamp
        self.progressMs = progressMs
        self.isPlaying = isPlaying
        self.item = item
        self.currentlyPlayingType = currentlyPlayingType
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case device, repeatState, shuffleState, context, timestamp, progressMs, isPlaying, item
        case currentlyPlayingType, actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = try container.decodeIfPresent(SpotifyDevice.self, forKey: .device)
        repeatState = try container.decodeIfPresent(RepeatMode.self, forKey: .repeatState) ?? .off
        shuffleState = try container.decodeIfPresent(Bool.self, forKey: .shuffleState) ?? false
        context = try container.decodeIfPresent(PlaybackContext.self, forKey: .context)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp)
        progressMs = try container.decodeIfPresent(Int.self, forKey: .progressMs)
        isPlaying = try container.decodeIfPresent(Bool.self, forKey: .isPlaying) ?? false
        item = try container.decodeIfPresent(PlaybackItem.self, forKey: .item)
        currentlyPlayingType = try container.decodeIfPresent(String.self,
                                                             forKey: .currentlyPlayingType)
        actions = try container.decodeIfPresent(PlaybackActions.self, forKey: .actions)
            ?? PlaybackActions()
    }
}

enum RepeatMode: String, Decodable, Equatable, Sendable {
    case off
    case track
    case context

    /// Unknown values (the reference example literally says `"string"`) count as `off`.
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = RepeatMode(rawValue: value) ?? .off
    }
}

/// A Spotify Connect device.
struct SpotifyDevice: Decodable, Equatable, Sendable {
    /// Can be `null`.
    var id: String?
    var isActive: Bool
    var isPrivateSession: Bool?
    /// When true, the device accepts no Web API commands.
    var isRestricted: Bool
    var name: String
    /// For example `Computer`, `Smartphone`, `Speaker`. The case varies between examples.
    var type: String
    /// 0–100, can be `null`.
    var volumePercent: Int?
    var supportsVolume: Bool?

    init(id: String? = nil, isActive: Bool = true, isPrivateSession: Bool? = nil,
         isRestricted: Bool = false, name: String, type: String, volumePercent: Int? = nil,
         supportsVolume: Bool? = nil) {
        self.id = id
        self.isActive = isActive
        self.isPrivateSession = isPrivateSession
        self.isRestricted = isRestricted
        self.name = name
        self.type = type
        self.volumePercent = volumePercent
        self.supportsVolume = supportsVolume
    }

    private enum CodingKeys: String, CodingKey {
        case id, isActive, isPrivateSession, isRestricted, name, type, volumePercent
        case supportsVolume
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isPrivateSession = try container.decodeIfPresent(Bool.self, forKey: .isPrivateSession)
        isRestricted = try container.decodeIfPresent(Bool.self, forKey: .isRestricted) ?? false
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        volumePercent = try container.decodeIfPresent(Int.self, forKey: .volumePercent)
        supportsVolume = try container.decodeIfPresent(Bool.self, forKey: .supportsVolume)
    }
}

/// What the item plays from: a playlist, album, artist, show… (`context.type`).
struct PlaybackContext: Decodable, Equatable, Sendable {
    var type: String
    /// For example `spotify:playlist:37i9dQZF1DXcBWIGoYBM5M`.
    var uri: String
    var externalUrls: ExternalURLs?

    init(type: String, uri: String, externalUrls: ExternalURLs? = nil) {
        self.type = type
        self.uri = uri
        self.externalUrls = externalUrls
    }
}

/// `external_urls`. Kept as a string because the reference examples use `"string"`, and an
/// unusable URL must not break decoding.
struct ExternalURLs: Decodable, Equatable, Sendable {
    var spotify: String?

    init(spotify: String? = nil) {
        self.spotify = spotify
    }
}

struct SpotifyImage: Decodable, Equatable, Sendable {
    var url: String
    /// Can be `null`.
    var width: Int?
    var height: Int?

    init(url: String, width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.width = width
        self.height = height
    }
}

/// The currently playing track or episode, chosen by its `type` field.
enum PlaybackItem: Decodable, Equatable, Sendable {
    case track(SpotifyTrack)
    case episode(SpotifyEpisode)
    /// A type the app does not know yet. The reference asks clients to check `type`.
    case unsupported(type: String)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "track": self = .track(try SpotifyTrack(from: decoder))
        case "episode": self = .episode(try SpotifyEpisode(from: decoder))
        default: self = .unsupported(type: type)
        }
    }
}

struct SpotifyTrack: Decodable, Equatable, Sendable {
    /// `nil` for local files.
    var id: String?
    var name: String
    var uri: String?
    var durationMs: Int
    var explicit: Bool
    var isLocal: Bool
    var album: AlbumSummary?
    var artists: [ArtistSummary]
    var externalUrls: ExternalURLs?

    init(id: String? = nil, name: String, uri: String? = nil, durationMs: Int,
         explicit: Bool = false, isLocal: Bool = false, album: AlbumSummary? = nil,
         artists: [ArtistSummary] = [], externalUrls: ExternalURLs? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
        self.durationMs = durationMs
        self.explicit = explicit
        self.isLocal = isLocal
        self.album = album
        self.artists = artists
        self.externalUrls = externalUrls
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, uri, durationMs, explicit, isLocal, album, artists, externalUrls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        explicit = try container.decodeIfPresent(Bool.self, forKey: .explicit) ?? false
        isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal) ?? false
        album = try container.decodeIfPresent(AlbumSummary.self, forKey: .album)
        artists = try container.decodeIfPresent([ArtistSummary].self, forKey: .artists) ?? []
        externalUrls = try container.decodeIfPresent(ExternalURLs.self, forKey: .externalUrls)
    }
}

struct AlbumSummary: Decodable, Equatable, Sendable {
    var id: String?
    var name: String
    var uri: String?
    var images: [SpotifyImage]
    var externalUrls: ExternalURLs?

    init(id: String? = nil, name: String, uri: String? = nil, images: [SpotifyImage] = [],
         externalUrls: ExternalURLs? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
        self.images = images
        self.externalUrls = externalUrls
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, uri, images, externalUrls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        images = try container.decodeIfPresent([SpotifyImage].self, forKey: .images) ?? []
        externalUrls = try container.decodeIfPresent(ExternalURLs.self, forKey: .externalUrls)
    }
}

struct ArtistSummary: Decodable, Equatable, Sendable {
    var id: String?
    var name: String
    var uri: String?

    init(id: String? = nil, name: String, uri: String? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
    }
}

/// A podcast episode. Episodes have `show` instead of `album` and `artists`.
struct SpotifyEpisode: Decodable, Equatable, Sendable {
    var id: String?
    var name: String
    var uri: String?
    var durationMs: Int
    var explicit: Bool
    var images: [SpotifyImage]
    var show: ShowSummary?
    var externalUrls: ExternalURLs?

    init(id: String? = nil, name: String, uri: String? = nil, durationMs: Int,
         explicit: Bool = false, images: [SpotifyImage] = [], show: ShowSummary? = nil,
         externalUrls: ExternalURLs? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
        self.durationMs = durationMs
        self.explicit = explicit
        self.images = images
        self.show = show
        self.externalUrls = externalUrls
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, uri, durationMs, explicit, images, show, externalUrls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        explicit = try container.decodeIfPresent(Bool.self, forKey: .explicit) ?? false
        images = try container.decodeIfPresent([SpotifyImage].self, forKey: .images) ?? []
        show = try container.decodeIfPresent(ShowSummary.self, forKey: .show)
        externalUrls = try container.decodeIfPresent(ExternalURLs.self, forKey: .externalUrls)
    }
}

struct ShowSummary: Decodable, Equatable, Sendable {
    var id: String?
    var name: String
    var uri: String?
    var images: [SpotifyImage]?
    var externalUrls: ExternalURLs?

    init(id: String? = nil, name: String, uri: String? = nil, images: [SpotifyImage]? = nil,
         externalUrls: ExternalURLs? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
        self.images = images
        self.externalUrls = externalUrls
    }
}

/// Playback actions that the current context does not allow (`actions`).
///
/// The documentation and real answers disagree on the shape:
/// - Historically, and as `docs/03-spotify-api.md` describes, Spotify answers
///   `"actions": {"disallows": {"resuming": true}}`: `true` means **not allowed**.
/// - The current "Get Playback State" reference (checked 2026-11-17) lists the ten booleans
///   directly under `actions`, without `disallows`, and does not say whether `true` means
///   allowed or not allowed.
///
/// Only the `disallows` form is interpreted. The flat form is kept as-is in `flatFlags`
/// and **not** used to disable anything: reading it the wrong way round would disable every
/// allowed control. Reviewed in milestone 3 (2026-11-17), see docs/03-spotify-api.md,
/// "`actions`", and `ControlAvailability`.
struct PlaybackActions: Decodable, Equatable, Sendable {
    enum Action: String, CaseIterable, Sendable {
        // camelCase because keys go through `convertFromSnakeCase`.
        case interruptingPlayback
        case pausing
        case resuming
        case seeking
        case skippingNext
        case skippingPrev
        case togglingRepeatContext
        case togglingShuffle
        case togglingRepeatTrack
        case transferringPlayback
    }

    /// Actions with `true` inside `disallows`.
    var disallowed: Set<Action>
    /// Booleans found directly under `actions` (undocumented meaning, see above).
    var flatFlags: [String: Bool]

    init(disallowed: Set<Action> = [], flatFlags: [String: Bool] = [:]) {
        self.disallowed = disallowed
        self.flatFlags = flatFlags
    }

    func isDisallowed(_ action: Action) -> Bool {
        disallowed.contains(action)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var disallowed: Set<Action> = []
        var flatFlags: [String: Bool] = [:]

        if let disallows = try? container.nestedContainer(keyedBy: AnyCodingKey.self,
                                                           forKey: AnyCodingKey("disallows")) {
            for action in Action.allCases
            where (try? disallows.decodeIfPresent(Bool.self,
                                                  forKey: AnyCodingKey(action.rawValue))) == true {
                disallowed.insert(action)
            }
        }
        for action in Action.allCases {
            if let value = try? container.decodeIfPresent(Bool.self,
                                                          forKey: AnyCodingKey(action.rawValue)) {
                flatFlags[action.rawValue] = value
            }
        }
        self.init(disallowed: disallowed, flatFlags: flatFlags)
    }
}

/// A coding key built from any string, for objects whose keys we look up one by one.
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
