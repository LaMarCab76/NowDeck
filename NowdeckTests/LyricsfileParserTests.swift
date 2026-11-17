import XCTest
@testable import Nowdeck

final class LyricsfileParserTests: XCTestCase {
    /// `examples/word-synced.lyricsfile.yaml` of the Lyricsfile specification
    /// (github.com/tranxuanthang/lyricsfile, CC0), the format LRCLIB documents for `lyricsfile`.
    private let specWordSynced = """
    version: '1.0'

    metadata:
      title: 'Small Hours'
      artist: 'Example Artist'
      language: 'en'

    lines:
      - text: 'Stay until the morning'
        start_ms: 4200
        end_ms: 6800
        words:
          - text: 'Stay '
            start_ms: 4200
            end_ms: 4800
          - text: 'until '
            start_ms: 4800
            end_ms: 5400
          - text: 'the '
            start_ms: 5400
            end_ms: 5750
          - text: 'morning'
            start_ms: 5750
            end_ms: 6800

    plain: |
      Stay until the morning
    """

    /// Start of the `lyricsfile` LRCLIB returns for the docs' `/api/get` example (record
    /// 3396226), as LRCLIB serializes it: no word timings, an empty line for the break.
    private let lrclibLineSynced = """
    version: '1.0'
    metadata:
      title: I Want to Live
      artist: Borislav Slavov
      album: Baldur's Gate 3 (Original Game Soundtrack)
      duration_ms: 233000
      instrumental: false
    lines:
    - text: I feel your breath upon my neck
      start_ms: 17120
      end_ms: 20410
    - text: ''
      start_ms: 49720
      end_ms: 51120
    """

    func testSpecificationExample() throws {
        let lyrics = try XCTUnwrap(LyricsfileParser.parse(specWordSynced))
        XCTAssertEqual(lyrics.sync, .word)
        XCTAssertEqual(lyrics.stanzas.count, 1)

        let line = try XCTUnwrap(lyrics.stanzas.first?.lines.first)
        XCTAssertEqual(line.startMs, 4_200)
        XCTAssertEqual(line.text, "Stay until the morning")
        XCTAssertEqual(line.words, [
            LyricsWord(startMs: 4_200, text: "Stay "),
            LyricsWord(startMs: 4_800, text: "until "),
            LyricsWord(startMs: 5_400, text: "the "),
            LyricsWord(startMs: 5_750, text: "morning"),
        ])
    }

    func testDocumentWithoutWordTimingsIsLeftToTheLRC() throws {
        XCTAssertNil(try LyricsfileParser.parse(lrclibLineSynced))
    }

    func testInstrumentalGivesNil() throws {
        let yaml = """
        version: '1.0'
        metadata:
          title: 'Quiet Transit'
          artist: 'Example Ensemble'
          duration_ms: 240000
          instrumental: true
        """
        XCTAssertNil(try LyricsfileParser.parse(yaml))
    }

    func testUnknownVersionIsRejected() {
        let yaml = specWordSynced.replacingOccurrences(of: "version: '1.0'", with: "version: '2.0'")
        XCTAssertThrowsError(try LyricsfileParser.parse(yaml)) {
            XCTAssertEqual($0 as? LyricsfileParser.ParseError, .unsupportedVersion("2.0"))
        }
    }

    func testBrokenYAMLIsRejected() {
        XCTAssertThrowsError(try LyricsfileParser.parse("version: '1.0'\nlines: [unclosed"))
        XCTAssertThrowsError(try LyricsfileParser.parse("- just\n- a list"))
    }

    func testAliasBombIsRejected() {
        // Each level multiplies the previous one by 9: decoding would build a huge tree.
        var yaml = "version: '1.0'\na: &a [x, x, x, x, x, x, x, x, x]\n"
        var previous = "a"
        for level in ["b", "c", "d", "e", "f", "g"] {
            yaml += "\(level): &\(level) [" + Array(repeating: "*\(previous)", count: 9).joined(separator: ", ") + "]\n"
            previous = level
        }
        XCTAssertThrowsError(try LyricsfileParser.parse(yaml)) {
            XCTAssertEqual($0 as? LyricsfileParser.ParseError, .tooComplex)
        }
    }

    func testWordsWithoutTimeTakeThePreviousOne() throws {
        let yaml = """
        version: '1.0'
        metadata: { title: T, artist: A }
        lines:
          - text: 'Word sync'
            start_ms: 1000
            words:
              - text: 'Word '
              - text: 'sync'
                start_ms: 1500
          - text: 'Line without words'
            start_ms: 3000
        """
        let lyrics = try XCTUnwrap(LyricsfileParser.parse(yaml))
        let lines = lyrics.stanzas.flatMap(\.lines)
        XCTAssertEqual(lines[0].words.map(\.startMs), [1_000, 1_500])
        XCTAssertEqual(lines[1].words, [LyricsWord(startMs: 3_000, text: "Line without words")],
                       "A line without words is one single word")
    }

    func testLinesAreGroupedLikeTheLRC() throws {
        let yaml = """
        version: '1.0'
        metadata: { title: T, artist: A }
        lines:
          - { text: 'One', start_ms: 1000, end_ms: 2000, words: [{ text: 'One', start_ms: 1000 }] }
          - { text: 'Two', start_ms: 2000, end_ms: 3000, words: [{ text: 'Two', start_ms: 2000 }] }
          - { text: '', start_ms: 3000, end_ms: 9000 }
          - { text: 'Three', start_ms: 9000, words: [{ text: 'Three', start_ms: 9000 }] }
        """
        let lyrics = try XCTUnwrap(LyricsfileParser.parse(yaml))
        XCTAssertEqual(lyrics.stanzas.map(\.text), ["One Two", "Three"])
        XCTAssertEqual(lyrics.stanzas.first?.endMs, 3_000)
    }

    // MARK: Choosing the mode from an LRCLIB record

    func testRecordWithWordSyncUsesTheLyricsfile() {
        let record = LRCLIBRecord(id: 1, hasWordSync: true, syncedLyrics: "[00:04.20] Stay until the morning",
                                  lyricsfile: specWordSynced)
        XCTAssertEqual(record.syncedLyricsForDisplay()?.sync, .word)
    }

    func testRecordFallsBackToTheLRCWhenTheLyricsfileCannotBeRead() {
        let record = LRCLIBRecord(id: 1, hasWordSync: true, syncedLyrics: "[00:04.20] Stay until the morning",
                                  lyricsfile: "version: '9'")
        XCTAssertEqual(record.syncedLyricsForDisplay()?.sync, .line)
    }

    func testRecordWithoutWordSyncUsesTheLRC() {
        let record = LRCLIBRecord(id: 1, hasWordSync: false, syncedLyrics: "[00:17.12] I feel your breath",
                                  lyricsfile: lrclibLineSynced)
        XCTAssertEqual(record.syncedLyricsForDisplay()?.sync, .line)
    }

    func testPlainOnlyOrInstrumentalRecordsHaveNoLyricsToShow() {
        XCTAssertNil(LRCLIBRecord(id: 1, plainLyrics: "Just text").syncedLyricsForDisplay())
        XCTAssertNil(LRCLIBRecord(id: 1, instrumental: true, syncedLyrics: "[00:01.00] x").syncedLyricsForDisplay())
    }
}
