import Foundation

/// A timed line as it comes out of a parser, before grouping.
struct TimedLyricsLine: Equatable, Sendable {
    var startMs: Int
    /// End time, when the source has one (Lyricsfile `end_ms`). LRC lines never do.
    var endMs: Int?
    var text: String
    /// Word timings (Lyricsfile). `nil` for LRC lines.
    var words: [LyricsWord]?
    /// Position of the line's paragraph in the source file: LRC lines separated by a blank
    /// line get different blocks. Lyricsfile lines are all in block 0.
    var block: Int = 0

    /// An empty timed line marks a break (LRC `[01:02.00]` with no text, or a Lyricsfile line
    /// with empty `text`). LRCLIB uses them for instrumental parts.
    var isBreak: Bool {
        let joinedWords = words?.map(\.text).joined() ?? ""
        return text.trimmingCharacters(in: .whitespaces).isEmpty
            && joinedWords.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Groups timed lines into the stanzas shown in lyrics mode (docs/04-letras.md).
///
/// 1. Stanzas are separated by blank lines of the LRC (different `block`) or by empty timed
///    lines (breaks).
/// 2. If that gives a single stanza, lines are split where there is a pause of more than 4 s.
/// 3. Finally, no stanza keeps more than `maxLinesPerStanza` lines (2): longer ones are cut
///    in pairs. This is also the docs' "every 2 lines" last resort, and it keeps the current
///    stanza inside the lyrics area of the mockup at 30 pt (see the milestone report).
enum StanzaBuilder {
    static let pauseThresholdMs = 4_000
    static let maxLinesPerStanza = 2

    static func stanzas(from lines: [TimedLyricsLine]) -> [LyricsStanza] {
        // Stable sort by time: lines with several timestamps (repeated choruses) come out of
        // the parser in file order.
        let sorted = lines.enumerated()
            .sorted { ($0.element.startMs, $0.offset) < ($1.element.startMs, $1.offset) }
            .map(\.element)

        var groups = groupByBlocksAndBreaks(sorted)
        if groups.count <= 1 {
            groups = groups.flatMap(splitByPauses)
        }
        return groups.flatMap(splitLongGroup)
    }

    private struct Group {
        var lines: [TimedLyricsLine] = []
        var endMs: Int?
    }

    private static func groupByBlocksAndBreaks(_ lines: [TimedLyricsLine]) -> [Group] {
        var groups: [Group] = []
        var current = Group()

        func close(endMs: Int? = nil) {
            guard !current.lines.isEmpty else { return }
            current.endMs = endMs
            groups.append(current)
            current = Group()
        }

        for line in lines {
            if line.isBreak {
                close(endMs: line.startMs)
                continue
            }
            if let last = current.lines.last, last.block != line.block {
                close()
            }
            current.lines.append(line)
        }
        close()
        return groups
    }

    private static func splitByPauses(_ group: Group) -> [Group] {
        var result: [Group] = []
        var current = Group()
        for line in group.lines {
            if let last = current.lines.last {
                // Without an end time (LRC) the pause is measured from the previous start.
                let gap = line.startMs - (last.endMs ?? last.startMs)
                if gap > pauseThresholdMs {
                    result.append(current)
                    current = Group()
                }
            }
            current.lines.append(line)
        }
        current.endMs = group.endMs
        if !current.lines.isEmpty { result.append(current) }
        return result
    }

    private static func splitLongGroup(_ group: Group) -> [LyricsStanza] {
        let chunks = stride(from: 0, to: group.lines.count, by: maxLinesPerStanza).map {
            Array(group.lines[$0..<min($0 + maxLinesPerStanza, group.lines.count)])
        }
        return chunks.enumerated().map { index, chunk in
            LyricsStanza(
                lines: chunk.map { LyricsLine(startMs: $0.startMs, text: $0.text, words: $0.words) },
                // Only the last piece keeps the explicit end of the original stanza.
                endMs: index == chunks.count - 1 ? group.endMs : nil
            )
        }
    }
}
