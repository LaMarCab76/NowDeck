import XCTest
@testable import Nowdeck

/// Milestone 8: with the library open, the devices sheet opens inside it, not behind it.
@MainActor
final class PlayerPresentationTests: XCTestCase {
    func testDevicesOpenOnThePlayerWhenNothingCoversIt() {
        let presentation = PlayerPresentation()
        XCTAssertEqual(presentation.visibleSurface, .player)

        presentation.showDevices()

        XCTAssertTrue(presentation.showsDevices)
        XCTAssertFalse(presentation.showsLibraryDevices)
    }

    func testDevicesOpenInsideTheLibraryWhileItCoversThePlayer() {
        let presentation = PlayerPresentation()
        presentation.showsLibrary = true
        XCTAssertEqual(presentation.visibleSurface, .library)

        presentation.showDevices()

        XCTAssertTrue(presentation.showsLibraryDevices,
                      "The library's own sheet: one presented by the player would open behind it")
        XCTAssertFalse(presentation.showsDevices)
    }

    func testThePlayerKeepsPollingOnlyUnderCoversThatShowThePlayback() {
        let presentation = PlayerPresentation()
        XCTAssertFalse(presentation.keepsPlayerPolling)

        presentation.showsQueue = true
        XCTAssertTrue(presentation.keepsPlayerPolling, "Cola's header follows the playback")
        presentation.showsQueue = false

        presentation.showsLibrary = true
        XCTAssertTrue(presentation.keepsPlayerPolling, "The mini player follows the playback")
        presentation.showsLibrary = false

        presentation.showsSettings = true
        XCTAssertFalse(presentation.keepsPlayerPolling)
        presentation.showsSettings = false

        presentation.showsDevices = true
        XCTAssertFalse(presentation.keepsPlayerPolling)
    }

    func testClosingTheLibraryBringsTheNoticesBackToThePlayer() {
        let presentation = PlayerPresentation()
        presentation.showsLibrary = true
        presentation.showsLibrary = false
        XCTAssertEqual(presentation.visibleSurface, .player)
    }

    /// The whole path: the mini player's play button gets a `404` while the library is open.
    func testNoActiveDeviceFromACommandOpensTheVisibleSheet() async throws {
        // Every path is stubbed, the artwork and the playlist name included.
        let (session, _) = StubURLProtocol.session { request in
            guard request.url?.host == "api.spotify.com",
                  request.url?.path.hasPrefix("/v1/playlists") == false
            else { return (.stub(404), Data()) }
            if request.httpMethod == "GET" {
                return (.stub(200), try PlaybackJSON(isPlaying: false).data())
            }
            return (.stub(404), spotifyErrorJSON(status: 404, message: "Player command failed: No active device found"))
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let player = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
        _ = await player.poll()
        XCTAssertEqual(player.status, .active)
        let controls = PlayerControlsModel(player: player, confirmDelay: 0, noticeDuration: 30)
        let presentation = PlayerPresentation()
        presentation.showsLibrary = true
        let subscription = controls.noActiveDevice.sink { presentation.showDevices() }
        defer { subscription.cancel() }

        controls.playPause()

        try await eventually { presentation.showsLibraryDevices }
        XCTAssertFalse(presentation.showsDevices)
        XCTAssertEqual(controls.notice, .noActiveDevice)
    }
}
