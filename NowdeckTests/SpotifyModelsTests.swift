import XCTest
@testable import Nowdeck

final class SpotifyModelsTests: XCTestCase {
    private func decode(_ data: Data) throws -> PlaybackState {
        try SpotifyAPI.makeDecoder().decode(PlaybackState.self, from: data)
    }

    // MARK: Reference examples (developer.spotify.com)

    func testDecodesReferencePlaybackExample() throws {
        let state = try decode(Fixture.data("playback-state-reference"))

        let device = try XCTUnwrap(state.device)
        XCTAssertEqual(device.id, "string")
        XCTAssertEqual(device.name, "Kitchen speaker")
        XCTAssertEqual(device.type, "computer")
        XCTAssertEqual(device.volumePercent, 59)
        XCTAssertEqual(device.supportsVolume, false)

        XCTAssertEqual(state.repeatState, .off, "Unknown values ('string') fall back to off")
        XCTAssertFalse(state.shuffleState)
        XCTAssertEqual(state.context?.type, "string")
        XCTAssertEqual(state.progressMs, 0)
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.currentlyPlayingType, "string")

        guard case .track(let track) = state.item else { return XCTFail("Expected a track") }
        XCTAssertEqual(track.album?.id, "2up3OPMp9Tb4dAKM2erWXQ")
        XCTAssertEqual(track.album?.uri, "spotify:album:2up3OPMp9Tb4dAKM2erWXQ")
        XCTAssertEqual(track.album?.images.first?.width, 300)
        XCTAssertEqual(track.artists.map(\.name), ["string"])
        XCTAssertFalse(track.isLocal)

        // The reference lists the action booleans directly under `actions`, with no
        // documented meaning: they are kept but never used to disable controls.
        XCTAssertEqual(state.actions.flatFlags.count, 10)
        XCTAssertTrue(state.actions.disallowed.isEmpty)
    }

    func testDecodesReferenceEpisodeAsItem() throws {
        let state = try decode(Fixture.playbackWithEpisode())

        guard case .episode(let episode) = state.item else { return XCTFail("Expected an episode") }
        XCTAssertEqual(episode.name,
                       "Starting Your Own Podcast: Tips, Tricks, and Advice From Anchor Creators")
        XCTAssertEqual(episode.durationMs, 1_686_230)
        XCTAssertEqual(episode.uri, "spotify:episode:0zLhl3WsOCQHbe1BPTiHgr")
        XCTAssertEqual(episode.show?.name, "string")
        XCTAssertEqual(episode.images.first?.url,
                       "https://i.scdn.co/image/ab67616d00001e02ff9ca10b55ce82ae553c8228")

        let item = try XCTUnwrap(NowPlaying(state: state))
        XCTAssertEqual(item.subtitle, "string", "Episodes show the podcast name")
        XCTAssertEqual(item.durationMs, 1_686_230)
        XCTAssertEqual(item.itemURL?.absoluteString,
                       "https://open.spotify.com/episode/0zLhl3WsOCQHbe1BPTiHgr",
                       "Falls back to the URI when external_urls is not a Spotify link")
    }

    // MARK: Realistic answer

    func testDecodesRealisticPlayback() throws {
        let state = try decode(Fixture.data("playback-state-playing"))

        XCTAssertEqual(state.repeatState, .context)
        XCTAssertTrue(state.shuffleState)
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.progressMs, 84_000)
        XCTAssertEqual(state.context?.uri, "spotify:playlist:3cEYpjA9oz9GiPac4AsH4n")
        XCTAssertEqual(state.actions.disallowed, [.resuming, .skippingPrev])
        XCTAssertTrue(state.actions.isDisallowed(.skippingPrev))
        XCTAssertFalse(state.actions.isDisallowed(.skippingNext))

        let item = try XCTUnwrap(NowPlaying(state: state))
        XCTAssertEqual(item.title, "Vereda Mojada")
        XCTAssertEqual(item.subtitle, "Los Tilos del Sur, Ana Prado")
        XCTAssertTrue(item.isExplicit)
        XCTAssertEqual(item.durationMs, 227_000)
        XCTAssertEqual(item.artworkURL?.absoluteString,
                       "https://i.scdn.co/image/ab67616d0000b273aaaaaaaaaaaaaaaaaaaaaaaa",
                       "The largest image")
        XCTAssertEqual(item.artworkCacheKey, "6akEvsycLGftJxYudPjmqK")
        XCTAssertEqual(item.itemURL?.absoluteString,
                       "https://open.spotify.com/track/2TpxZ7JUBn3uw46aR7qd6V")
    }

    func testMissingOptionalFieldsDoNotBreakDecoding() throws {
        let json = """
        {"device": {"id": null, "is_active": true, "name": "Parlante", "type": "Speaker",
                    "volume_percent": null},
         "is_playing": false, "item": null, "currently_playing_type": "unknown"}
        """
        let state = try decode(Data(json.utf8))
        XCTAssertNil(state.device?.id)
        XCTAssertNil(state.device?.volumePercent)
        XCTAssertNil(state.item)
        XCTAssertEqual(state.repeatState, .off)
        XCTAssertNil(NowPlaying(state: state), "No item: nothing to show")
    }

    func testAdKeepsThePlayer() throws {
        let state = try decode(Data(#"{"is_playing": true, "item": null, "currently_playing_type": "ad"}"#.utf8))
        let item = try XCTUnwrap(NowPlaying(state: state))
        XCTAssertTrue(item.isAd)
        XCTAssertNil(item.artworkURL)
    }

    func testUnknownItemTypeIsNotShown() throws {
        let state = try decode(Data(#"{"is_playing": true, "item": {"type": "chapter", "name": "x"}}"#.utf8))
        XCTAssertEqual(state.item, .unsupported(type: "chapter"))
        XCTAssertNil(NowPlaying(state: state))
    }

    func testErrorBody() throws {
        let body = try JSONDecoder().decode(
            SpotifyErrorBody.self,
            from: spotifyErrorJSON(status: 429, message: "x", reason: "QUOTA_EXCEEDED"))
        XCTAssertEqual(body.error.reason, SpotifyErrorBody.quotaExceededReason)
    }

    // MARK: Origin

    func testPlaylistOriginNeedsItsName() throws {
        let state = try decode(Fixture.data("playback-state-playing"))
        let origin = try XCTUnwrap(PlaybackOrigin.from(context: state.context, item: state.item))
        XCTAssertEqual(origin.kind, .playlist)
        XCTAssertNil(origin.name)
        XCTAssertEqual(origin.playlistID, "3cEYpjA9oz9GiPac4AsH4n")
        XCTAssertEqual(origin.url?.absoluteString,
                       "https://open.spotify.com/playlist/3cEYpjA9oz9GiPac4AsH4n")
    }

    func testAlbumAndArtistNamesComeFromTheItem() throws {
        let state = try decode(Fixture.data("playback-state-playing"))

        let album = PlaybackOrigin.from(
            context: PlaybackContext(type: "album", uri: "spotify:album:6akEvsycLGftJxYudPjmqK"),
            item: state.item)
        XCTAssertEqual(album?.kind, .album)
        XCTAssertEqual(album?.name, "Vereda Mojada")
        XCTAssertNil(album?.playlistID)

        let artist = PlaybackOrigin.from(
            context: PlaybackContext(type: "artist", uri: "spotify:artist:1vCWHaC5f2uS3yhpwWbIA6"),
            item: state.item)
        XCTAssertEqual(artist?.name, "Ana Prado")

        let otherAlbum = PlaybackOrigin.from(
            context: PlaybackContext(type: "album", uri: "spotify:album:0000000000000000000000"),
            item: state.item)
        XCTAssertNil(otherAlbum?.name, "Unknown name: show only the type")
    }

    func testLikedSongsAndUnknownContexts() {
        let liked = PlaybackOrigin.from(
            context: PlaybackContext(type: "collection", uri: "spotify:user:abc:collection"),
            item: nil)
        XCTAssertEqual(liked?.kind, .likedSongs)
        XCTAssertNil(PlaybackOrigin.from(context: PlaybackContext(type: "string", uri: "string"),
                                         item: nil))
        XCTAssertNil(PlaybackOrigin.from(context: nil, item: nil))
    }

    func testSpotifyURI() {
        XCTAssertEqual(SpotifyURI("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")?.webURL?.absoluteString,
                       "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M")
        XCTAssertNil(SpotifyURI("spotify:user:abc:collection"))
        XCTAssertNil(SpotifyURI("spotify:playlist:../../evil"))
        XCTAssertNil(SpotifyURI("string"))
    }

    @MainActor
    func testOnlySpotifyLinksAreOpened() {
        let page = URL(string: "https://open.spotify.com/album/6akEvsycLGftJxYudPjmqK")!
        XCTAssertEqual(SpotifyLink.sanitized(page), page)
        XCTAssertEqual(SpotifyLink.sanitized(URL(string: "https://example.com/x")), SpotifyLink.home)
        XCTAssertEqual(SpotifyLink.sanitized(URL(string: "http://open.spotify.com/x")), SpotifyLink.home)
        XCTAssertEqual(SpotifyLink.sanitized(nil), SpotifyLink.home)
    }
}
