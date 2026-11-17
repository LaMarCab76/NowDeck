import XCTest
@testable import Nowdeck

final class ControlAvailabilityTests: XCTestCase {
    func testEverythingAllowedWithoutDisallows() throws {
        let availability = ControlAvailability(playback: try PlaybackJSON().state())
        XCTAssertTrue(availability.playPause)
        XCTAssertTrue(availability.previous)
        XCTAssertTrue(availability.next)
        XCTAssertTrue(availability.shuffle)
        XCTAssertTrue(availability.repeatMode)
        XCTAssertTrue(availability.seek)
    }

    func testDisallowsDisableTheirControls() throws {
        let state = try PlaybackJSON(disallows: ["skipping_prev", "skipping_next",
                                                 "toggling_shuffle", "seeking"]).state()
        let availability = ControlAvailability(playback: state)
        XCTAssertFalse(availability.previous)
        XCTAssertFalse(availability.next)
        XCTAssertFalse(availability.shuffle)
        XCTAssertFalse(availability.seek)
        XCTAssertTrue(availability.playPause)
    }

    func testPlayPauseDependsOnTheCurrentState() throws {
        // `resuming` forbidden only matters while paused, `pausing` only while playing.
        XCTAssertTrue(ControlAvailability(
            playback: try PlaybackJSON(isPlaying: true, disallows: ["resuming"]).state()).playPause)
        XCTAssertFalse(ControlAvailability(
            playback: try PlaybackJSON(isPlaying: false, disallows: ["resuming"]).state()).playPause)
        XCTAssertFalse(ControlAvailability(
            playback: try PlaybackJSON(isPlaying: true, disallows: ["pausing"]).state()).playPause)
    }

    func testRestrictedDeviceDisablesEverything() throws {
        let availability = ControlAvailability(playback: try PlaybackJSON(isRestricted: true).state())
        XCTAssertEqual(availability, .none)
    }

    func testNoPlaybackDisablesEverything() {
        XCTAssertEqual(ControlAvailability(playback: nil), .none)
    }

    /// The flat booleans of the current reference have no documented meaning: they never
    /// disable anything.
    func testFlatActionFlagsAreIgnored() throws {
        let json = #"{"is_playing": true, "actions": {"pausing": true, "skipping_next": true, "resuming": false}}"#
        let state = try SpotifyAPI.makeDecoder().decode(PlaybackState.self, from: Data(json.utf8))
        XCTAssertEqual(state.actions.flatFlags["pausing"], true)
        let availability = ControlAvailability(playback: state)
        XCTAssertTrue(availability.playPause)
        XCTAssertTrue(availability.next)
    }

    // MARK: Repeat cycle

    func testRepeatCycle() {
        let actions = PlaybackActions()
        XCTAssertEqual(ControlAvailability.nextRepeatMode(after: .off, actions: actions), .context)
        XCTAssertEqual(ControlAvailability.nextRepeatMode(after: .context, actions: actions), .track)
        XCTAssertEqual(ControlAvailability.nextRepeatMode(after: .track, actions: actions), .off)
    }

    func testRepeatCycleSkipsForbiddenModes() {
        let noTrack = PlaybackActions(disallowed: [.togglingRepeatTrack])
        XCTAssertEqual(ControlAvailability.nextRepeatMode(after: .off, actions: noTrack), .context)
        XCTAssertEqual(ControlAvailability.nextRepeatMode(after: .context, actions: noTrack), .off)

        let noContext = PlaybackActions(disallowed: [.togglingRepeatContext])
        XCTAssertEqual(ControlAvailability.nextRepeatMode(after: .off, actions: noContext), .track)
        XCTAssertEqual(ControlAvailability.nextRepeatMode(after: .track, actions: noContext), .off)

        let neither = PlaybackActions(disallowed: [.togglingRepeatContext, .togglingRepeatTrack])
        XCTAssertNil(ControlAvailability.nextRepeatMode(after: .off, actions: neither))
    }

    // MARK: Control order from the theme

    func testDefaultOrderMatchesTheMockup() {
        let layout = PlayerControlLayout(controls: [.shuffle, .repeatMode, .lyrics, .volume])
        XCTAssertEqual(layout.leading, [.shuffle, .repeatMode])
        XCTAssertEqual(layout.trailing, [.lyrics, .volume])
    }

    func testWithoutLyricsVolumeStaysOnTheRight() {
        let layout = PlayerControlLayout(controls: [.shuffle, .repeatMode, .volume])
        XCTAssertEqual(layout.leading, [.shuffle, .repeatMode])
        XCTAssertEqual(layout.trailing, [.volume])
    }

    func testThemeOrderIsFollowed() {
        let layout = PlayerControlLayout(controls: [.volume, .lyrics, .repeatMode, .shuffle])
        XCTAssertEqual(layout.leading, [.volume, .lyrics])
        XCTAssertEqual(layout.trailing, [.repeatMode, .shuffle])

        let two = PlayerControlLayout(controls: [.volume, .shuffle])
        XCTAssertEqual(two.leading, [.volume])
        XCTAssertEqual(two.trailing, [.shuffle])
    }

    func testEmptyAndRepeatedControls() {
        let empty = PlayerControlLayout(controls: [])
        XCTAssertEqual(empty.leading, [])
        XCTAssertEqual(empty.trailing, [])

        let repeated = PlayerControlLayout(controls: [.volume, .volume, .shuffle])
        XCTAssertEqual(repeated.leading, [.volume])
        XCTAssertEqual(repeated.trailing, [.shuffle])
    }

    @MainActor
    func testThemeStoreFeedsTheLayout() {
        var theme = Theme.default
        theme.player = Theme.Player(artworkPosition: .left, controls: [.volume, .shuffle, .repeatMode])
        let store = ThemeStore(theme: theme)
        let layout = PlayerControlLayout(controls: store.playerControls)
        XCTAssertEqual(layout.leading, [.volume, .shuffle])
        XCTAssertEqual(layout.trailing, [.repeatMode])
        XCTAssertFalse(store.showsLyricsButton)
    }
}
