import Foundation

/// Parses LRC text (LRCLIB's `syncedLyrics`) into stanzas.
///
/// Supported, per docs/04-letras.md:
/// - `[mm:ss.xx] text`, with `.` or `:` before the fraction and 0 to 3 fraction digits (the
///   same forms LRCLIB's own parser accepts);
/// - several timestamps on one line (`[00:12.00][01:30.00] chorus`);
/// - the `[offset:±ms]` tag. As in the LRC convention, a positive offset makes the lyrics
///   appear sooner: `time = timestamp − offset`;
/// - blank lines between stanzas and empty timed lines (breaks).
///
/// Other ID tags (`[ar:…]`, `[ti:…]`, …) and lines without a timestamp are ignored. Inline
/// word times of the "enhanced LRC" variant (`<00:12.34>`) are removed from the text.
enum LRCParser {
    static func parse(_ lrc: String) -> SyncedLyrics? {
        let lines = timedLines(lrc)
        let stanzas = StanzaBuilder.stanzas(from: lines)
        guard !stanzas.isEmpty else { return nil }
        return SyncedLyrics(sync: .line, stanzas: stanzas)
    }

    /// The timed lines in file order, one per timestamp, with the offset applied.
    static func timedLines(_ lrc: String) -> [TimedLyricsLine] {
        var result: [TimedLyricsLine] = []
        var offsetMs = 0
        var block = 0

        let rawLines = lrc.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                block += 1
                continue
            }
            let (timestamps, rest) = leadingTimestamps(of: Substring(line))
            if timestamps.isEmpty {
                if let value = offsetTagValue(line) { offsetMs = value }
                continue
            }
            // Collapsing spaces also cleans the gaps left by removed inline word times.
            let text = removingInlineWordTimes(String(rest))
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .joined(separator: " ")
            for timestamp in timestamps {
                result.append(TimedLyricsLine(startMs: timestamp, text: text, block: block))
            }
        }

        return result.map { line in
            var shifted = line
            shifted.startMs = max(0, line.startMs - offsetMs)
            return shifted
        }
    }

    // MARK: - Timestamps

    /// Reads every `[mm:ss.xx]` at the start of the line (spaces between them are allowed).
    static func leadingTimestamps(of line: Substring) -> ([Int], Substring) {
        var timestamps: [Int] = []
        var rest = line
        while true {
            let trimmed = rest.drop(while: { $0 == " " || $0 == "\t" })
            guard trimmed.first == "[", let close = trimmed.firstIndex(of: "]") else { break }
            let inside = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
            guard let milliseconds = timestamp(inside) else { break }
            timestamps.append(milliseconds)
            rest = trimmed[trimmed.index(after: close)...]
        }
        return (timestamps, timestamps.isEmpty ? line : rest)
    }

    /// `mm:ss`, `mm:ss.f`, `mm:ss.ff`, `mm:ss.fff` (or `:` instead of `.`) → milliseconds.
    static func timestamp(_ text: Substring) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let minutesText = parts[0]
        var secondsText = parts[1]
        var fractionText: Substring = ""
        if parts.count == 3 {
            fractionText = parts[2]
        } else if let dot = secondsText.firstIndex(of: ".") {
            fractionText = secondsText[secondsText.index(after: dot)...]
            secondsText = secondsText[..<dot]
            guard !fractionText.isEmpty else { return nil }
        }

        guard isDigits(minutesText), minutesText.count <= 4,
              isDigits(secondsText), (1...2).contains(secondsText.count),
              fractionText.isEmpty || (isDigits(fractionText) && fractionText.count <= 3),
              let minutes = Int(minutesText), let seconds = Int(secondsText)
        else { return nil }

        var milliseconds = 0
        if let fraction = Int(fractionText) {
            switch fractionText.count {
            case 1: milliseconds = fraction * 100
            case 2: milliseconds = fraction * 10
            default: milliseconds = fraction
            }
        }
        return minutes * 60_000 + seconds * 1_000 + milliseconds
    }

    private static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: - Tags

    /// The value of a whole-line `[offset:+250]` tag, if this line is one.
    static func offsetTagValue(_ line: String) -> Int? {
        guard line.hasPrefix("["), line.hasSuffix("]"),
              let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[line.index(after: line.startIndex)..<colon]
        guard key.trimmingCharacters(in: .whitespaces).lowercased() == "offset" else { return nil }
        let value = line[line.index(after: colon)..<line.index(before: line.endIndex)]
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // `Int("+250")` accepts the sign.
        return Int(trimmed)
    }

    /// Removes every `<mm:ss.xx>` from the text; other `<…>` are kept.
    static func removingInlineWordTimes(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<") {
            result += rest[..<open]
            let afterOpen = rest[rest.index(after: open)...]
            if let close = afterOpen.firstIndex(of: ">"), timestamp(afterOpen[..<close]) != nil {
                rest = afterOpen[afterOpen.index(after: close)...]
            } else {
                result.append("<")
                rest = afterOpen
            }
        }
        result += rest
        return result
    }
}
