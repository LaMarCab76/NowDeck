import XCTest
@testable import Nowdeck

@MainActor
final class AppPreferencesTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaultsAreNoOffsetAndNoFolders() {
        let preferences = AppPreferences(defaults: freshDefaults())
        XCTAssertEqual(preferences.lyricsOffsetMs, 0)
        XCTAssertFalse(preferences.usesPlaylistFolders)
        XCTAssertFalse(preferences.hasAnsweredPlaylistFolders)
    }

    func testValuesSurviveANewInstance() {
        let defaults = freshDefaults()
        let preferences = AppPreferences(defaults: defaults)
        preferences.lyricsOffsetMs = 400
        preferences.answerPlaylistFolders(enabled: true)

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.lyricsOffsetMs, 400)
        XCTAssertTrue(reloaded.usesPlaylistFolders)
        XCTAssertTrue(reloaded.hasAnsweredPlaylistFolders)
    }

    func testOffsetIsRoundedToTheStepAndClamped() {
        XCTAssertEqual(AppPreferences.clampedOffset(149), 100)
        XCTAssertEqual(AppPreferences.clampedOffset(-260), -300)
        XCTAssertEqual(AppPreferences.clampedOffset(9_000), 3_000)
        XCTAssertEqual(AppPreferences.clampedOffset(-9_000), -3_000)

        let defaults = freshDefaults()
        let preferences = AppPreferences(defaults: defaults)
        preferences.lyricsOffsetMs = 5_000
        XCTAssertEqual(preferences.lyricsOffsetMs, 3_000)
        XCTAssertEqual(AppPreferences(defaults: defaults).lyricsOffsetMs, 3_000,
                       "The clamped value is the one saved")
    }

    func testOffsetMovesTheLyricsPosition() {
        let start = Date(timeIntervalSince1970: 1_000)
        let playing = LyricsPlayback(progressMs: 10_000, isPlaying: true, timestamp: start)
        let later = start.addingTimeInterval(2)
        XCTAssertEqual(playing.lyricsPositionMs(at: later, offsetMs: 0), 12_000)
        XCTAssertEqual(playing.lyricsPositionMs(at: later, offsetMs: 500), 12_500,
                       "A positive offset shows the lyrics earlier")
        XCTAssertEqual(playing.lyricsPositionMs(at: later, offsetMs: -700), 11_300)

        let paused = LyricsPlayback(progressMs: 300, isPlaying: false, timestamp: start)
        XCTAssertEqual(paused.lyricsPositionMs(at: later, offsetMs: -1_000), 0,
                       "Never before the start of the track")
    }

    func testOffsetTexts() {
        XCTAssertTrue(LyricsOffsetRow.valueText(0).hasSuffix(" s"))
        XCTAssertTrue(LyricsOffsetRow.valueText(300).hasPrefix("+"))
        XCTAssertTrue(LyricsOffsetRow.valueText(-1_500).hasPrefix("−"))
    }
}
