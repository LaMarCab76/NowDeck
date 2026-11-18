#if DEBUG
import Foundation

/// The made-up library of the demo. Every name, cover and lyric here is invented for
/// Nowdeck's screenshots: no real artists, albums, playlists or lyrics.
///
/// Answers are built as JSON objects with the Web API's snake_case keys, so they go through
/// the same decoders as real answers.
enum DemoContent {
    typealias JSON = [String: Any]

    // MARK: Catalog

    struct Track {
        var id: String
        var name: String
        var artist: String
        var album: String
        var cover: String
        var durationMs: Int
    }

    struct Album {
        var id: String
        var name: String
        var artist: String
        var year: String
        var cover: String
        var trackCount: Int
    }

    struct Playlist {
        var id: String
        var name: String
        var owner: String
        var cover: String
        var trackCount: Int
    }

    private static let lowTide = DemoArtwork.url(from: "1b2a4a", to: "f2766b", shape: .sun)
    private static let neonOrchard = DemoArtwork.url(from: "2d0b45", to: "3ee8b5", shape: .dots)
    private static let afterlight = DemoArtwork.url(from: "f6c66b", to: "c2412d", shape: .rings)
    private static let copperLines = DemoArtwork.url(from: "4a2c1d", to: "e0a060", shape: .stripes)
    private static let harborLights = DemoArtwork.url(from: "0f3d3e", to: "7fd1c7", shape: .rings)
    private static let smallFires = DemoArtwork.url(from: "3a0d0d", to: "ff8a3d", shape: .sun)
    private static let fieldNotes = DemoArtwork.url(from: "dfe7d3", to: "5d7a4f", shape: .stripes)
    private static let glowSeason = DemoArtwork.url(from: "ff5f9e", to: "6a3df0", shape: .plain)

    /// What plays: the first track of the queue's album.
    static let nowPlaying = Track(id: "demotrack01", name: "Glass Harbor", artist: "Velvet Static",
                                  album: "Low Tide Signals", cover: lowTide, durationMs: 227_000)

    static let queue: [Track] = [
        Track(id: "demotrack02", name: "Paper Satellites", artist: "Velvet Static",
              album: "Low Tide Signals", cover: lowTide, durationMs: 204_000),
        Track(id: "demotrack03", name: "Neon Orchard", artist: "Mira Kestrel",
              album: "Neon Orchard", cover: neonOrchard, durationMs: 191_000),
        Track(id: "demotrack04", name: "Slow Weather", artist: "The Quiet Hours",
              album: "Afterlight Radio", cover: afterlight, durationMs: 256_000),
        Track(id: "demotrack05", name: "Copper Lines", artist: "Juno Arden",
              album: "Copper Lines EP", cover: copperLines, durationMs: 182_000),
        Track(id: "demotrack06", name: "Midnight Ferry", artist: "Lumen & Ash",
              album: "Harbor Lights", cover: harborLights, durationMs: 239_000),
        Track(id: "demotrack07", name: "Lanterns", artist: "Odessa Vale",
              album: "Small Fires", cover: smallFires, durationMs: 214_000),
        Track(id: "demotrack08", name: "Static Bloom", artist: "Velvet Static",
              album: "Low Tide Signals", cover: lowTide, durationMs: 198_000),
    ]

    static let playlists: [Playlist] = [
        Playlist(id: "demoplaylist01", name: "Desk Focus", owner: "You",
                 cover: DemoArtwork.url(from: "12324a", to: "4f8cff", shape: .rings), trackCount: 48),
        Playlist(id: "demoplaylist02", name: "Late Night Drive", owner: "You",
                 cover: DemoArtwork.url(from: "120c2c", to: "c03fd0", shape: .stripes), trackCount: 62),
        Playlist(id: "demoplaylist03", name: "Sunday Slow", owner: "You",
                 cover: DemoArtwork.url(from: "f3e2c7", to: "d9824b", shape: .sun), trackCount: 35),
        Playlist(id: "demoplaylist04", name: "Coffee & Code", owner: "You",
                 cover: DemoArtwork.url(from: "3b2618", to: "c49a6c", shape: .dots), trackCount: 80),
        Playlist(id: "demoplaylist05", name: "Rainy Window", owner: "Marina",
                 cover: DemoArtwork.url(from: "2b3a4a", to: "9fb3c8", shape: .stripes), trackCount: 27),
        Playlist(id: "demoplaylist06", name: "Morning Run", owner: "You",
                 cover: DemoArtwork.url(from: "ffcf3d", to: "ff4f4f", shape: .plain), trackCount: 41),
        Playlist(id: "demoplaylist07", name: "Deep Work Ambient", owner: "You",
                 cover: DemoArtwork.url(from: "0b1f1a", to: "2fa37c", shape: .rings), trackCount: 112),
        Playlist(id: "demoplaylist08", name: "Throwback Mix", owner: "Leo",
                 cover: DemoArtwork.url(from: "6a1b9a", to: "ffb74d", shape: .dots), trackCount: 54),
    ]

    static let albums: [Album] = [
        Album(id: "demoalbum01", name: "Low Tide Signals", artist: "Velvet Static", year: "2025",
              cover: lowTide, trackCount: 11),
        Album(id: "demoalbum02", name: "Neon Orchard", artist: "Mira Kestrel", year: "2024",
              cover: neonOrchard, trackCount: 9),
        Album(id: "demoalbum03", name: "Afterlight Radio", artist: "The Quiet Hours", year: "2023",
              cover: afterlight, trackCount: 12),
        Album(id: "demoalbum04", name: "Harbor Lights", artist: "Lumen & Ash", year: "2022",
              cover: harborLights, trackCount: 10),
        Album(id: "demoalbum05", name: "Small Fires", artist: "Odessa Vale", year: "2026",
              cover: smallFires, trackCount: 8),
        Album(id: "demoalbum06", name: "Copper Lines EP", artist: "Juno Arden", year: "2025",
              cover: copperLines, trackCount: 5),
        Album(id: "demoalbum07", name: "Field Notes", artist: "Pale Meridian", year: "2021",
              cover: fieldNotes, trackCount: 10),
        Album(id: "demoalbum08", name: "Glow Season", artist: "Sunday Arcade", year: "2024",
              cover: glowSeason, trackCount: 13),
    ]

    /// The playlist the track plays from.
    static var currentPlaylist: Playlist { playlists[0] }

    // MARK: Playback

    /// Where the track was when the app launched: about 1:32, in the middle of the lyrics.
    private static let startProgressMs = 92_000
    /// Moves the position with the real clock, so the progress bar and the lyrics advance.
    private static let launchedAt = Date()

    static func progressMs(now: Date = Date()) -> Int {
        let elapsed = Int(now.timeIntervalSince(launchedAt) * 1000)
        return (startProgressMs + elapsed) % nowPlaying.durationMs
    }

    static var devices: [JSON] { [
        device(id: "demodevice01", name: "Living Room Speaker", type: "Speaker", active: true,
               volume: 62),
        device(id: "demodevice02", name: "Work Laptop", type: "Computer", active: false,
               volume: 40),
        device(id: "demodevice03", name: "Kitchen Radio", type: "Speaker", active: false,
               volume: 35),
        device(id: "demodevice04", name: "Bedroom TV", type: "TV", active: false, volume: 20),
    ] }

    static func playbackState() -> JSON {
        [
            "device": devices[0],
            "repeat_state": "off",
            "shuffle_state": false,
            "context": [
                "type": "playlist",
                "uri": "spotify:playlist:\(currentPlaylist.id)",
                "external_urls": ["spotify": "https://open.spotify.com/playlist/\(currentPlaylist.id)"],
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "progress_ms": progressMs(),
            "is_playing": true,
            "item": trackJSON(nowPlaying),
            "currently_playing_type": "track",
            "actions": ["disallows": ["resuming": true]],
        ]
    }

    static func queueJSON() -> JSON {
        ["currently_playing": trackJSON(nowPlaying), "queue": queue.map(trackJSON)]
    }

    static func devicesJSON() -> JSON {
        ["devices": devices]
    }

    static func recentlyPlayedJSON() -> JSON {
        ["items": [["track": trackJSON(nowPlaying), "played_at": "2026-11-18T12:00:00Z"]]]
    }

    // MARK: Library

    static func playlistsPage() -> JSON {
        page(playlists.map { playlist in
            [
                "id": playlist.id,
                "name": playlist.name,
                "uri": "spotify:playlist:\(playlist.id)",
                "images": [image(playlist.cover)],
                "owner": ["id": playlist.owner == "You" ? "demouser" : "demofriend",
                          "display_name": playlist.owner],
                "collaborative": false,
                "items": ["total": playlist.trackCount],
                "external_urls": ["spotify": "https://open.spotify.com/playlist/\(playlist.id)"],
            ]
        })
    }

    static func albumsPage() -> JSON {
        page(albums.map { ["added_at": "2026-11-01T12:00:00Z", "album": albumJSON($0)] })
    }

    static func showsPage() -> JSON {
        page([
            show(id: "demoshow01", name: "The Slow Build", episodes: 128,
                 cover: DemoArtwork.url(from: "222222", to: "e94f37", shape: .stripes)),
            show(id: "demoshow02", name: "Signal & Noise", episodes: 64,
                 cover: DemoArtwork.url(from: "0d2b45", to: "59c3c3", shape: .dots)),
            show(id: "demoshow03", name: "Desk Notes", episodes: 37,
                 cover: DemoArtwork.url(from: "f7f3e3", to: "8a817c", shape: .rings)),
        ])
    }

    static func audiobooksPage() -> JSON {
        page([[
            "id": "demobook01",
            "name": "The Lighthouse Keeper's Almanac",
            "uri": "spotify:audiobook:demobook01",
            "images": [image(DemoArtwork.url(from: "13293d", to: "e8c547", shape: .sun))],
            "authors": [["name": "R. T. Calloway"]],
            "narrators": [["name": "Ines Moreau"]],
            "total_chapters": 24,
        ]])
    }

    /// The same tracks for any album or playlist that is opened.
    static func collectionTracksPage(wrapped: Bool) -> JSON {
        let tracks = ([nowPlaying] + queue).map { track -> JSON in
            [
                "type": "track",
                "name": track.name,
                "uri": "spotify:track:\(track.id)",
                "duration_ms": track.durationMs,
                "explicit": false,
                "is_local": false,
                "artists": [["name": track.artist]],
            ]
        }
        return page(wrapped ? tracks.map { ["is_local": false, "item": $0] } : tracks)
    }

    static func searchJSON() -> JSON {
        [
            "tracks": page(([nowPlaying] + queue).map(trackJSON)),
            "albums": page(albums.map(albumJSON)),
            "playlists": playlistsPage(),
        ]
    }

    static func playlistName(id: String) -> JSON? {
        playlists.first { $0.id == id }.map { ["name": $0.name] }
    }

    static func artistJSON(id: String) -> JSON {
        // A soft gradient stands in for the artist photo (the "artista" background).
        ["id": id, "images": [image(DemoArtwork.url(from: "1d1a39", to: "e57a6a", shape: .plain))]]
    }

    // MARK: Lyrics

    /// Invented lyrics for "Glass Harbor" (LRC). Blank lines split the stanzas, and the empty
    /// timed lines are instrumental breaks, as on LRCLIB.
    static let lyrics = """
    [00:14.20]Salt on the window, the city's asleep,
    [00:21.80]ferries keep humming the promises we keep.
    [00:29.40]I traced your name in the fog on the glass,
    [00:36.90]watching the harbor lights flicker and pass.
    [00:44.50]

    [00:52.10]Oh, hold the line, hold the light,
    [00:58.60]we're only glass in the harbor tonight.
    [01:05.30]Every wave says it's not too late,
    [01:12.00]every signal says wait, just wait.
    [01:18.80]

    [01:22.50]Static on the radio, a song we used to know,
    [01:30.10]cranes like sleeping giants standing in a row.
    [01:37.70]You said the tide would bring us something new,
    [01:45.20]so I left the porch light on for you.

    [01:53.80]Oh, hold the line, hold the light,
    [02:00.30]we're only glass in the harbor tonight.
    [02:07.00]Every wave says it's not too late,
    [02:13.60]every signal says wait, just wait.
    [02:20.20]

    [02:25.00]And if the morning never finds this shore,
    [02:32.40]I'll keep the echo of an open door.
    [02:40.00]Paper boats and borrowed time,
    [02:47.50]your heartbeat ringing out in mine.

    [02:58.00]Oh, hold the line, hold the light,
    [03:04.50]we're only glass in the harbor tonight.
    [03:11.20]Every wave says it's not too late,
    [03:17.80]every signal says wait, just wait.
    [03:26.00]
    """

    /// LRCLIB's answer for a track, or `nil` (`404`) for every track but the one playing.
    static func lyricsRecord(trackName: String?) -> JSON? {
        guard trackName == nowPlaying.name else { return nil }
        return [
            "id": 1,
            "trackName": nowPlaying.name,
            "artistName": nowPlaying.artist,
            "albumName": nowPlaying.album,
            "duration": Double(nowPlaying.durationMs) / 1000,
            "instrumental": false,
            "plainLyrics": NSNull(),
            "syncedLyrics": lyrics,
        ]
    }

    // MARK: Helpers

    private static func trackJSON(_ track: Track) -> JSON {
        let album = albums.first { $0.name == track.album }
        return [
            "type": "track",
            "id": track.id,
            "name": track.name,
            "uri": "spotify:track:\(track.id)",
            "duration_ms": track.durationMs,
            "explicit": false,
            "is_local": false,
            "album": [
                "id": album?.id ?? "demoalbum00",
                "name": track.album,
                "uri": "spotify:album:\(album?.id ?? "demoalbum00")",
                "images": [image(track.cover)],
            ],
            "artists": [["id": artistID(track.artist), "name": track.artist,
                         "uri": "spotify:artist:\(artistID(track.artist))"]],
            "external_urls": ["spotify": "https://open.spotify.com/track/\(track.id)"],
        ]
    }

    private static func albumJSON(_ album: Album) -> JSON {
        [
            "id": album.id,
            "name": album.name,
            "uri": "spotify:album:\(album.id)",
            "album_type": album.trackCount > 6 ? "album" : "single",
            "total_tracks": album.trackCount,
            "release_date": "\(album.year)-03-14",
            "images": [image(album.cover)],
            "artists": [["id": artistID(album.artist), "name": album.artist]],
            "external_urls": ["spotify": "https://open.spotify.com/album/\(album.id)"],
        ]
    }

    private static func show(id: String, name: String, episodes: Int, cover: String) -> JSON {
        [
            "added_at": "2026-11-01T12:00:00Z",
            "show": [
                "id": id,
                "name": name,
                "uri": "spotify:show:\(id)",
                "images": [image(cover)],
                "total_episodes": episodes,
            ] as JSON,
        ]
    }

    private static func device(id: String, name: String, type: String, active: Bool,
                               volume: Int) -> JSON {
        [
            "id": id,
            "is_active": active,
            "is_private_session": false,
            "is_restricted": false,
            "name": name,
            "type": type,
            "volume_percent": volume,
            "supports_volume": true,
        ]
    }

    private static func image(_ url: String) -> JSON {
        ["url": url, "width": 640, "height": 640]
    }

    private static func page(_ items: [JSON]) -> JSON {
        ["items": items, "limit": 50, "offset": 0, "total": items.count, "next": NSNull()]
    }

    private static func artistID(_ name: String) -> String {
        "demoartist" + name.lowercased().filter(\.isLetter)
    }
}
#endif
