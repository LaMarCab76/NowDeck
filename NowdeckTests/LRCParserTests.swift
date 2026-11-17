import XCTest
@testable import Nowdeck

final class LRCParserTests: XCTestCase {
    // MARK: Timestamps

    func testTimestampForms() {
        XCTAssertEqual(LRCParser.timestamp("00:17.12"), 17_120)
        XCTAssertEqual(LRCParser.timestamp("01:02.5"), 62_500)
        XCTAssertEqual(LRCParser.timestamp("01:02.345"), 62_345)
        XCTAssertEqual(LRCParser.timestamp("0:02"), 2_000)
        XCTAssertEqual(LRCParser.timestamp("00:03:4"), 3_400, "LRCLIB also accepts ':' before the fraction")
        XCTAssertEqual(LRCParser.timestamp("12:00.00"), 720_000)
        XCTAssertNil(LRCParser.timestamp("ar:Someone"))
        XCTAssertNil(LRCParser.timestamp("00:17."))
        XCTAssertNil(LRCParser.timestamp("00:173.1"))
        XCTAssertNil(LRCParser.timestamp("offset:+200"))
    }

    func testSeveralTimestampsOnOneLineRepeatTheLine() {
        let lines = LRCParser.timedLines("""
        [00:10.00][01:30.00] Chorus line
        [00:20.00] Verse line
        """)
        XCTAssertEqual(lines.map(\.startMs), [10_000, 90_000, 20_000])
        XCTAssertEqual(lines.map(\.text), ["Chorus line", "Chorus line", "Verse line"])

        let stanzas = LRCParser.parse("""
        [00:10.00][01:30.00] Chorus line
        [00:20.00] Verse line
        """)!.stanzas
        let starts = stanzas.flatMap(\.lines).map(\.startMs)
        XCTAssertEqual(starts, [10_000, 20_000, 90_000], "Lines end up in time order")
    }

    func testTimestampsSeparatedBySpaces() {
        let lines = LRCParser.timedLines("[00:01.00] [00:05.00] Twice")
        XCTAssertEqual(lines.map(\.startMs), [1_000, 5_000])
        XCTAssertEqual(lines.map(\.text), ["Twice", "Twice"])
    }

    // MARK: Tags

    func testPositiveOffsetMakesLyricsAppearSooner() {
        let lines = LRCParser.timedLines("""
        [ar:Someone]
        [offset:+500]
        [00:10.00] Hello
        """)
        XCTAssertEqual(lines.map(\.startMs), [9_500])
    }

    func testNegativeOffsetDelaysLyricsAndAppliesToEarlierLines() {
        let lines = LRCParser.timedLines("""
        [00:10.00] Hello
        [offset:-250]
        """)
        XCTAssertEqual(lines.map(\.startMs), [10_250])
    }

    func testOffsetNeverGoesBelowZero() {
        let lines = LRCParser.timedLines("[offset:2000]\n[00:01.00] Early")
        XCTAssertEqual(lines.map(\.startMs), [0])
    }

    func testIDTagsAndUntimedLinesAreIgnored() {
        let lines = LRCParser.timedLines("""
        [ti:Song]
        [ar:Artist]
        [length: 03:20]
        [Verse 1]
        [00:01.00] Only this
        """)
        XCTAssertEqual(lines.map(\.text), ["Only this"])
    }

    func testInlineWordTimesAreRemoved() {
        let lines = LRCParser.timedLines("[00:01.00] <00:01.00> Hello <00:01.50> world <b>")
        XCTAssertEqual(lines.first?.text, "Hello world <b>")
    }

    func testWindowsLineEndings() {
        let lyrics = LRCParser.parse("[00:01.00] One\r\n\r\n[00:05.00] Two\r\n")
        XCTAssertEqual(lyrics?.stanzas.map(\.text), ["One", "Two"])
    }

    func testNoTimedLinesGivesNil() {
        XCTAssertNil(LRCParser.parse("Just plain text\nwithout times"))
        XCTAssertNil(LRCParser.parse(""))
    }

    // MARK: Stanzas

    func testBlankLinesSeparateStanzas() {
        let lyrics = LRCParser.parse("""
        [00:01.00] One
        [00:02.00] Two

        [00:03.00] Three
        """)
        XCTAssertEqual(lyrics?.sync, .line)
        XCTAssertEqual(lyrics?.stanzas.map(\.text), ["One Two", "Three"])
    }

    /// LRCLIB marks instrumental parts with an empty timed line (real format of the record in
    /// the docs' `/api/get` example).
    func testEmptyTimedLinesSeparateStanzasAndMarkTheirEnd() {
        let lyrics = LRCParser.parse("""
        [00:17.12] I feel your breath upon my neck
        [00:20.41] A soft caress as cold as death
        [00:49.72]
        [00:51.12] It's not my fault
        [00:53.94] I'm not to blame
        [03:25.72]
        """)!
        XCTAssertEqual(lyrics.stanzas.map(\.text), [
            "I feel your breath upon my neck A soft caress as cold as death",
            "It's not my fault I'm not to blame",
        ])
        XCTAssertEqual(lyrics.stanzas.map(\.endMs), [49_720, 205_720])
    }

    func testRepeatedChorusKeepsItsOwnStanza() {
        let lyrics = LRCParser.parse("""
        [00:01.00] Verse one

        [00:05.00][00:15.00] Chorus

        [00:10.00] Verse two
        """)!
        XCTAssertEqual(lyrics.stanzas.map(\.text), ["Verse one", "Chorus", "Verse two", "Chorus"])
    }

    func testWithoutBlankLinesGroupsByPausesLongerThanFourSeconds() {
        let lyrics = LRCParser.parse("""
        [00:01.00] A
        [00:03.00] B
        [00:09.00] C
        [00:12.00] D
        """)!
        XCTAssertEqual(lyrics.stanzas.map(\.text), ["A B", "C D"])
    }

    func testWithoutBlankLinesOrPausesGroupsEveryTwoLines() {
        let lyrics = LRCParser.parse("""
        [00:01.00] A
        [00:02.00] B
        [00:03.00] C
        [00:04.00] D
        [00:05.00] E
        """)!
        XCTAssertEqual(lyrics.stanzas.map(\.text), ["A B", "C D", "E"])
    }

    func testLongStanzasAreCutInPairs() {
        let lyrics = LRCParser.parse("""
        [00:01.00] A
        [00:02.00] B
        [00:03.00] C
        [00:04.00]
        [00:05.00] D
        """)!
        XCTAssertEqual(lyrics.stanzas.map(\.text), ["A B", "C", "D"])
        XCTAssertEqual(lyrics.stanzas.map(\.endMs), [nil, 4_000, nil],
                       "Only the last piece keeps the end of the original stanza")
    }
}
