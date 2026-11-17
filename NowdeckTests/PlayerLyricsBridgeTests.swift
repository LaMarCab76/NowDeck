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
        XCTAssertEqual(named.sourceLabel, "Desde la playlist")
        XCTAssertEqual(named.sourceName, "Para laburar")
        XCTAssertEqual(named.artist, "A, B")
        XCTAssertEqual(named.deviceName, "MacBook Pro")

        let unnamed = LyricsModeContent(item: item, origin: PlaybackOrigin(kind: .playlist), deviceName: nil)
        XCTAssertNil(unnamed.sourceLabel)
        XCTAssertEqual(unnamed.sourceName, "Desde una playlist")

        XCTAssertNil(LyricsModeContent(item: item, origin: nil, deviceName: nil).sourceName)
    }
}
