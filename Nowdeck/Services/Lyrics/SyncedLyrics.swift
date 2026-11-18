import Foundation

/// Lyrics ready to display, already grouped in stanzas.
///
/// Built by `LRCParser` (line-synced, from `syncedLyrics`) or `LyricsfileParser` (word-synced,
/// from `lyricsfile`). All times are milliseconds from the start of the track, with any LRC
/// `[offset:]` already applied.
struct SyncedLyrics: Equatable, Sendable {
    enum Sync: Equatable, Sendable {
        /// Word-level timings: sung words are highlighted (docs/04, "Por palabra").
        case word
        /// Line-level timings: the whole current stanza is shown (docs/04, "Estrofa completa").
        case line
    }

    let sync: Sync
    let stanzas: [LyricsStanza]
}

struct LyricsStanza: Equatable, Sendable {
    let lines: [LyricsLine]
    /// When the stanza explicitly ends: the time of an empty timed line that closes it (an
    /// instrumental break in the LRC or the Lyricsfile). `nil` when the stanza runs until the
    /// next one starts.
    let endMs: Int?

    var startMs: Int { lines[0].startMs }

    /// Every word of the stanza in order. Lines are joined with a space so the stanza reads
    /// as one paragraph (the design asks for no forced line breaks).
    var words: [LyricsWord] {
        var result: [LyricsWord] = []
        for line in lines {
            if let last = result.last, !last.text.isEmpty, !(last.text.last?.isWhitespace ?? true) {
                result[result.count - 1] = LyricsWord(startMs: last.startMs, text: last.text + " ")
            }
            result.append(contentsOf: line.words)
        }
        return result
    }

    /// The stanza as a single paragraph.
    var text: String {
        words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LyricsLine: Equatable, Sendable {
    let startMs: Int
    let text: String
    /// Word timings. For line-synced lyrics there is a single "word" with the whole line, so
    /// both kinds can be handled the same way.
    let words: [LyricsWord]

    init(startMs: Int, text: String, words: [LyricsWord]? = nil) {
        self.startMs = startMs
        self.text = text
        self.words = words ?? [LyricsWord(startMs: startMs, text: text)]
    }
}

struct LyricsWord: Equatable, Sendable {
    let startMs: Int
    /// Includes the whitespace that follows the word, as in the Lyricsfile format.
    let text: String
}

/// "Estilo de las letras" (Ajustes → Reproductor): how lyrics with word timings are shown.
/// Line-synced lyrics always show the whole stanza, whatever the style.
enum LyricsStyle: String, CaseIterable, Sendable {
    /// Sung words are highlighted as they play, when the lyrics have word timings.
    case byWord = "word"
    /// The whole current stanza at once, even when the lyrics have word timings.
    case stanza

    /// What a new install uses: the richest mode the lyrics allow.
    static let defaultStyle: LyricsStyle = .byWord
}

extension SyncedLyrics {
    /// The lyrics as lyrics mode shows them with `style`. In stanza style, word-synced lyrics
    /// are treated as line-synced: the stanzas and their times stay the same, only the
    /// highlight goes away (and the view refreshes at the slower stanza pace).
    func displayed(as style: LyricsStyle) -> SyncedLyrics {
        switch style {
        case .byWord: return self
        case .stanza: return SyncedLyrics(sync: .line, stanzas: stanzas)
        }
    }
}
