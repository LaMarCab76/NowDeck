import XCTest
@testable import Nowdeck

final class LyricsTimelineTests: XCTestCase {
    /// Three stanzas: [1 s, 3 s] · break at 8 s · [10 s] · [20 s, 22 s].
    private let lineLyrics = LRCParser.parse("""
    [00:01.00] One
    [00:03.00] Two
    [00:08.00]

    [00:10.00] Three

    [00:20.00] Four
    [00:22.00] Five
    """)!

    // MARK: Current and next stanza

    func testBeforeTheFirstLineTheFirstStanzaWaits() {
        let frame = LyricsTimeline.frame(for: lineLyrics, atMs: 500)
        XCTAssertEqual(frame, LyricsFrame(primaryIndex: 0, isPrimaryActive: false, nextIndex: 1, sungWordCount: 0))
    }

    func testCurrentStanzaHoldsTheLastLineAtOrBeforeThePosition() {
        XCTAssertEqual(LyricsTimeline.frame(for: lineLyrics, atMs: 1_000)?.primaryIndex, 0)
        XCTAssertEqual(LyricsTimeline.frame(for: lineLyrics, atMs: 5_000)?.primaryIndex, 0)
        XCTAssertEqual(LyricsTimeline.frame(for: lineLyrics, atMs: 5_000)?.nextIndex, 1)

        let third = LyricsTimeline.frame(for: lineLyrics, atMs: 21_000)
        XCTAssertEqual(third?.primaryIndex, 2)
        XCTAssertEqual(third?.isPrimaryActive, true)
        XCTAssertNil(third?.nextIndex, "The last stanza has no next one")
    }

    func testDuringABreakTheNextStanzaWaitsInTheBigSlot() {
        let frame = LyricsTimeline.frame(for: lineLyrics, atMs: 9_000)
        XCTAssertEqual(frame, LyricsFrame(primaryIndex: 1, isPrimaryActive: false, nextIndex: 2, sungWordCount: 0))
    }

    func testAfterTheLastStanzaEndsThereIsNothingToShow() {
        let lyrics = LRCParser.parse("[00:01.00] Last\n[00:05.00] ")!
        XCTAssertNotNil(LyricsTimeline.frame(for: lyrics, atMs: 4_999))
        XCTAssertNil(LyricsTimeline.frame(for: lyrics, atMs: 5_000))
    }

    func testLineSyncShowsTheWholeStanzaAsSung() {
        let frame = LyricsTimeline.frame(for: lineLyrics, atMs: 1_500)
        XCTAssertEqual(frame?.sungWordCount, lineLyrics.stanzas[0].words.count)
    }

    // MARK: Word by word

    private let wordLyrics = SyncedLyrics(sync: .word, stanzas: [
        LyricsStanza(lines: [
            LyricsLine(startMs: 1_000, text: "Stay until", words: [
                LyricsWord(startMs: 1_000, text: "Stay "),
                LyricsWord(startMs: 1_500, text: "until"),
            ]),
            LyricsLine(startMs: 2_000, text: "the morning", words: [
                LyricsWord(startMs: 2_000, text: "the "),
                LyricsWord(startMs: 2_400, text: "morning"),
            ]),
        ], endMs: nil),
        LyricsStanza(lines: [LyricsLine(startMs: 5_000, text: "Next")], endMs: nil),
    ])

    func testSungWordsAreTheOnesThatStartedAtOrBeforeThePosition() {
        XCTAssertEqual(LyricsTimeline.frame(for: wordLyrics, atMs: 1_000)?.sungWordCount, 1)
        XCTAssertEqual(LyricsTimeline.frame(for: wordLyrics, atMs: 1_499)?.sungWordCount, 1)
        XCTAssertEqual(LyricsTimeline.frame(for: wordLyrics, atMs: 1_500)?.sungWordCount, 2)
        XCTAssertEqual(LyricsTimeline.frame(for: wordLyrics, atMs: 2_399)?.sungWordCount, 3)
        XCTAssertEqual(LyricsTimeline.frame(for: wordLyrics, atMs: 4_000)?.sungWordCount, 4)
    }

    func testLinesOfAStanzaAreJoinedWithASpace() {
        XCTAssertEqual(wordLyrics.stanzas[0].words.map(\.text), ["Stay ", "until ", "the ", "morning"])
        XCTAssertEqual(wordLyrics.stanzas[0].text, "Stay until the morning")
    }

    // MARK: Playback interpolation

    private let start = Date(timeIntervalSince1970: 1_000)

    func testPositionAdvancesOnlyWhilePlaying() {
        let playing = LyricsPlayback(progressMs: 10_000, isPlaying: true, timestamp: start)
        XCTAssertEqual(playing.positionMs(at: start.addingTimeInterval(2.5)), 12_500)
        XCTAssertEqual(playing.positionMs(at: start.addingTimeInterval(-1)), 10_000)

        let paused = LyricsPlayback(progressMs: 10_000, isPlaying: false, timestamp: start)
        XCTAssertEqual(paused.positionMs(at: start.addingTimeInterval(5)), 10_000)
    }

    func testSmallPollDifferencesKeepTheInterpolation() {
        let anchor = LyricsPlayback(progressMs: 10_000, isPlaying: true, timestamp: start)
        let polled = LyricsPlayback(progressMs: 15_400, isPlaying: true, timestamp: start.addingTimeInterval(5))
        XCTAssertEqual(anchor.reconciled(with: polled), anchor)
    }

    func testJumpsOfMoreThanOneAndAHalfSecondsResync() {
        let anchor = LyricsPlayback(progressMs: 10_000, isPlaying: true, timestamp: start)
        let seek = LyricsPlayback(progressMs: 60_000, isPlaying: true, timestamp: start.addingTimeInterval(5))
        XCTAssertEqual(anchor.reconciled(with: seek), seek)

        let back = LyricsPlayback(progressMs: 13_400, isPlaying: true, timestamp: start.addingTimeInterval(5))
        XCTAssertEqual(anchor.reconciled(with: back), back)
    }

    func testPlayPauseChangesAlwaysResync() {
        let anchor = LyricsPlayback(progressMs: 10_000, isPlaying: true, timestamp: start)
        let paused = LyricsPlayback(progressMs: 10_900, isPlaying: false, timestamp: start.addingTimeInterval(1))
        XCTAssertEqual(anchor.reconciled(with: paused), paused)
    }

    // MARK: Lyrics style (Ajustes → Reproductor)

    func testByWordStyleKeepsTheWordHighlight() {
        let shown = wordLyrics.displayed(as: .byWord)
        XCTAssertEqual(shown, wordLyrics)
        XCTAssertEqual(LyricsTimeline.frame(for: shown, atMs: 1_200)?.sungWordCount, 1)
    }

    func testStanzaStyleShowsWordSyncedLyricsAsWholeStanzas() {
        let shown = wordLyrics.displayed(as: .stanza)
        XCTAssertEqual(shown.sync, .line)
        XCTAssertEqual(shown.stanzas, wordLyrics.stanzas, "Same stanzas and times")
        let frame = LyricsTimeline.frame(for: shown, atMs: 1_200)
        XCTAssertEqual(frame?.isPrimaryActive, true)
        XCTAssertEqual(frame?.sungWordCount, wordLyrics.stanzas[0].words.count,
                       "The whole stanza at once, not just the first word")
    }

    func testLineSyncedLyricsAreTheSameInEitherStyle() {
        XCTAssertEqual(lineLyrics.displayed(as: .byWord), lineLyrics)
        XCTAssertEqual(lineLyrics.displayed(as: .stanza), lineLyrics)
    }
}
