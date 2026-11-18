import XCTest
@testable import Nowdeck

final class PlayerLyricsBridgeTests: XCTestCase {
    private func state(_ item: PlaybackItem?, progress: Int = 42_000, playing: Bool = true) -> PlaybackState {
        PlaybackState(progressMs: progress, isPlaying: playing, item: item)
    }

    func testTrackUsesFirstArtistAndAlbum() {
        let track = SpotifyTrack(id: "abc123", name: "Vereda Mojada", durationMs: 200_000,
                                 album: AlbumSummary(name: "Lluvia"),
                                 artists: [ArtistSummary(name: "Los Tilos"), ArtistSummary(name: "Otro")])
        XCTAssertEqual(state(.track(track)).lyricsTrack,
                       LyricsTrack(spotifyID: "abc123", title: "Vereda Mojada", artist: "Los Tilos",
                                   album: "Lluvia", durationMs: 200_000))
    }

    func testEpisodesAndUnknownItemsHaveNoLyrics() {
        XCTAssertNil(state(nil).lyricsTrack)
        XCTAssertNil(state(.unsupported(type: "audiobook")).lyricsTrack)
        let noArtist = SpotifyTrack(name: "Sin artista", durationMs: 1_000, artists: [])
        XCTAssertNil(state(.track(noArtist)).lyricsTrack)
    }

    func testPlaybackCarriesPositionAndFetchTime() {
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let playback = state(nil, progress: 5_000, playing: false).lyricsPlayback(fetchedAt: fetchedAt)
        XCTAssertEqual(playback, LyricsPlayback(progressMs: 5_000, isPlaying: false, timestamp: fetchedAt))
    }

    func testSourceLabelAndName() throws {
        let track = SpotifyTrack(name: "T", durationMs: 1,
                                 artists: [ArtistSummary(name: "A"), ArtistSummary(name: "B")])
        let item = try XCTUnwrap(NowPlaying(state: state(.track(track))))
        let named = LyricsModeContent(item: item, origin: PlaybackOrigin(kind: .playlist, name: "Para laburar"),
                                      deviceName: "MacBook Pro")
        XCTAssertEqual(named.sourceLabel, "Reproduciendo desde")
        XCTAssertEqual(named.sourceName, "Para laburar")
        XCTAssertEqual(named.artist, "A, B")
        XCTAssertEqual(named.deviceName, "MacBook Pro")

        let unnamed = LyricsModeContent(item: item, origin: PlaybackOrigin(kind: .playlist), deviceName: nil)
        XCTAssertEqual(unnamed.sourceLabel, "Reproduciendo desde")
        XCTAssertEqual(unnamed.sourceName, "Una playlist")

        let withoutOrigin = LyricsModeContent(item: item, origin: nil, deviceName: nil)
        XCTAssertNil(withoutOrigin.sourceName)
        XCTAssertNil(withoutOrigin.sourceLabel)
    }

    func testOriginDisplayNameFallsBackToTheType() {
        XCTAssertEqual(PlaybackOrigin(kind: .playlist, name: "Para laburar").displayName, "Para laburar")
        XCTAssertEqual(PlaybackOrigin(kind: .playlist).displayName, "Una playlist",
                       "While the name is on its way")
        XCTAssertEqual(PlaybackOrigin(kind: .playlist, isNameUnavailable: true).displayName,
                       "Playlist de Spotify", "Radios and Spotify's own playlists")
        XCTAssertEqual(PlaybackOrigin(kind: .playlist, name: "", isNameUnavailable: true).displayName,
                       "Playlist de Spotify")
        XCTAssertEqual(PlaybackOrigin(kind: .album).displayName, "Un álbum")
        XCTAssertEqual(PlaybackOrigin(kind: .artist).displayName, "Un artista")
        XCTAssertEqual(PlaybackOrigin(kind: .show).displayName, "Un podcast")
        XCTAssertEqual(PlaybackOrigin(kind: .likedSongs).displayName, "Tus me gusta")
    }
}
