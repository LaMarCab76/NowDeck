import XCTest
@testable import Nowdeck

final class LyricsBrowsingTests: XCTestCase {
    /// Three stanzas: [1 s, 3 s] · break at 8 s · [10 s] · [20 s, 22 s].
    private let lyrics = LRCParser.parse("""
    [00:01.00] One
    [00:03.00] Two
    [00:08.00]

    [00:10.00] Three

    [00:20.00] Four
    [00:22.00] Five
    """)!

    func testDraggingUpMovesToLaterStanzas() {
        let step = LyricsBrowsing.stepHeight
        XCTAssertEqual(LyricsBrowsing.index(from: 0, translation: -step, count: 3), 1)
        XCTAssertEqual(LyricsBrowsing.index(from: 0, translation: -2 * step, count: 3), 2)
        XCTAssertEqual(LyricsBrowsing.index(from: 2, translation: step, count: 3), 1)
    }

    func testLessThanAStepStaysOnTheSameStanza() {
        let step = LyricsBrowsing.stepHeight
        XCTAssertEqual(LyricsBrowsing.index(from: 1, translation: -(step - 1), count: 3), 1)
        XCTAssertEqual(LyricsBrowsing.index(from: 1, translation: step - 1, count: 3), 1)
    }

    func testBrowsingStopsAtTheFirstAndLastStanza() {
        XCTAssertEqual(LyricsBrowsing.index(from: 0, translation: 500, count: 3), 0)
        XCTAssertEqual(LyricsBrowsing.index(from: 2, translation: -500, count: 3), 2)
    }

    func testSeekTargetIsTheStanzaStartMinusTheOffset() {
        let third = lyrics.stanzas[2]
        XCTAssertEqual(LyricsBrowsing.seekTarget(for: third, offsetMs: 0), 20_000)
        // Lyrics shown 500 ms earlier: the stanza appears when the playback is at 19.5 s.
        XCTAssertEqual(LyricsBrowsing.seekTarget(for: third, offsetMs: 500), 19_500)
        XCTAssertEqual(LyricsBrowsing.seekTarget(for: third, offsetMs: -500), 20_500)
        XCTAssertEqual(LyricsBrowsing.seekTarget(for: lyrics.stanzas[0], offsetMs: 2_000), 0,
                       "Never before the start")
    }

    func testSeekingToAStanzaShowsThatStanza() {
        for (index, stanza) in lyrics.stanzas.enumerated() {
            for offset in [-1_000, 0, 750] {
                let target = LyricsBrowsing.seekTarget(for: stanza, offsetMs: offset)
                let playback = LyricsPlayback(progressMs: target, isPlaying: false, timestamp: .now)
                let frame = LyricsTimeline.frame(
                    for: lyrics, atMs: playback.lyricsPositionMs(at: .now, offsetMs: offset))
                XCTAssertEqual(frame?.primaryIndex, index)
                XCTAssertEqual(frame?.isPrimaryActive, true)
            }
        }
    }

    func testBrowsingFrameShowsTheWholeStanzaAndTheNextOne() {
        XCTAssertEqual(LyricsBrowsing.frame(browsing: 1, in: lyrics),
                       LyricsFrame(primaryIndex: 1, isPrimaryActive: true, nextIndex: 2,
                                   sungWordCount: lyrics.stanzas[1].words.count))
        XCTAssertNil(LyricsBrowsing.frame(browsing: 2, in: lyrics)?.nextIndex)
        XCTAssertNil(LyricsBrowsing.frame(browsing: 3, in: lyrics))
    }

    func testADragStartsFromTheStanzaOnScreen() {
        XCTAssertEqual(LyricsBrowsing.startIndex(for: lyrics, atMs: 0), 0)
        XCTAssertEqual(LyricsBrowsing.startIndex(for: lyrics, atMs: 9_000), 1, "During a break, the upcoming one")
        XCTAssertEqual(LyricsBrowsing.startIndex(for: lyrics, atMs: 21_000), 2)
    }
}
