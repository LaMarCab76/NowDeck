import XCTest
@testable import Nowdeck

/// Answers lookups from a table, optionally waiting until released.
private actor FakeLyricsProvider: LyricsProviding {
    private let results: [String: LyricsLookup]
    private(set) var requested: [String] = []

    init(_ results: [String: LyricsLookup]) {
        self.results = results
    }

    func lyrics(for track: LyricsTrack) async -> LyricsLookup {
        requested.append(track.title)
        return results[track.title] ?? .notFound
    }
}

@MainActor
final class LyricsModeControllerTests: XCTestCase {
    private let lyrics = LRCParser.parse("[00:01.00] One")!

    private func track(_ title: String) -> LyricsTrack {
        LyricsTrack(spotifyID: title, title: title, artist: "A", album: nil, durationMs: 100_000)
    }

    /// Lets the lookup task finish.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func testTapShowsLyricsWhenFound() async {
        let controller = LyricsModeController(provider: FakeLyricsProvider(["Song": .found(lyrics)]))
        controller.toggle(for: track("Song"))
        XCTAssertTrue(controller.isButtonActive)
        XCTAssertFalse(controller.showsLyricsMode, "The normal view stays while loading")

        await settle()
        XCTAssertTrue(controller.showsLyricsMode)
        XCTAssertEqual(controller.lyrics, lyrics)
        XCTAssertNil(controller.notice)
    }

    func testNoLyricsShowsTheNoticeAndStaysInTheNormalView() async {
        let controller = LyricsModeController(provider: FakeLyricsProvider([:]), noticeDuration: 0.1)
        controller.toggle(for: track("Unknown"))
        await settle()
        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(controller.notice, .notFound)

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(controller.notice, "The notice goes away by itself")
    }

    func testFailedLookupShowsTheFailureNotice() async {
        let controller = LyricsModeController(provider: FakeLyricsProvider(["Song": .failed]))
        controller.toggle(for: track("Song"))
        await settle()
        XCTAssertEqual(controller.notice, .failed)
        XCTAssertFalse(controller.isButtonActive)
    }

    func testSecondTapTurnsLyricsModeOff() async {
        let controller = LyricsModeController(provider: FakeLyricsProvider(["Song": .found(lyrics)]))
        controller.toggle(for: track("Song"))
        await settle()
        controller.toggle(for: track("Song"))
        XCTAssertEqual(controller.state, .off)
    }

    func testTrackChangeWhileShowingLoadsTheNewLyrics() async {
        let other = LRCParser.parse("[00:01.00] Other")!
        let provider = FakeLyricsProvider(["Song": .found(lyrics), "Next": .found(other)])
        let controller = LyricsModeController(provider: provider)
        controller.toggle(for: track("Song"))
        await settle()

        controller.trackDidChange(to: track("Next"))
        XCTAssertTrue(controller.showsLyricsMode, "Lyrics mode stays open while the new lyrics load")
        XCTAssertNil(controller.lyrics)
        await settle()
        XCTAssertEqual(controller.lyrics, other)
    }

    func testTrackChangeToOneWithoutLyricsGoesBackToTheNormalView() async {
        let controller = LyricsModeController(provider: FakeLyricsProvider(["Song": .found(lyrics)]))
        controller.toggle(for: track("Song"))
        await settle()

        controller.trackDidChange(to: track("Instrumental"))
        await settle()
        XCTAssertFalse(controller.showsLyricsMode)
        XCTAssertEqual(controller.notice, .notFound)
    }

    func testTrackChangeWhileOffDoesNothing() async {
        let provider = FakeLyricsProvider(["Song": .found(lyrics)])
        let controller = LyricsModeController(provider: provider)
        controller.trackDidChange(to: track("Song"))
        await settle()
        XCTAssertEqual(controller.state, .off)
        let requested = await provider.requested
        XCTAssertTrue(requested.isEmpty)
    }
}
