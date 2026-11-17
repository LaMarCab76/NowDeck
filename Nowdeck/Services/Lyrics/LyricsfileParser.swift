import Foundation
import Yams

/// Parses LRCLIB's `lyricsfile` (YAML) into word-synced stanzas.
///
/// Field names follow the Lyricsfile 1.0 draft specification
/// (github.com/tranxuanthang/lyricsfile, `SPECIFICATION.md`, checked 2026-11-17):
///
/// ```yaml
/// version: '1.0'
/// metadata: { title, artist, album?, duration_ms?, offset_ms?, language?, instrumental? }
/// lines:
///   - text: 'Stay until the morning'
///     start_ms: 4200
///     end_ms: 6800          # optional
///     words:                # optional
///       - { text: 'Stay ', start_ms: 4200, end_ms: 4800 }
/// plain: |                  # optional
///   Stay until the morning
/// ```
///
/// Decisions (conservative, per the draft):
/// - `version` must be exactly `"1.0"`: the spec says readers must not treat an unknown
///   version as 1.0. Anything else is rejected and the caller falls back to `syncedLyrics`.
/// - `metadata.offset_ms` is ignored: the draft leaves its meaning unresolved.
/// - The document is data only. It is decoded into plain structs; YAML tags are never used to
///   build other types, and the size, depth and node count are limited before decoding
///   (aliases could otherwise expand a small document into a huge tree).
enum LyricsfileParser {
    enum ParseError: Error, Equatable {
        case tooLarge
        case invalidYAML
        case unsupportedVersion(String?)
        case tooComplex
        case invalidStructure
    }

    static let maxBytes = 512 * 1024
    static let maxNodes = 50_000
    static let maxDepth = 16

    /// The lyrics, or `nil` when the document has no word timings (or is instrumental): then
    /// the caller should use `syncedLyrics` instead.
    static func parse(_ yaml: String) throws -> SyncedLyrics? {
        let document = try decode(yaml)
        if document.metadata?.instrumental == true { return nil }

        let lines = (document.lines ?? []).compactMap(timedLine)
        guard lines.contains(where: { $0.words != nil }) else { return nil }

        let stanzas = StanzaBuilder.stanzas(from: lines)
        guard !stanzas.isEmpty else { return nil }
        return SyncedLyrics(sync: .word, stanzas: stanzas)
    }

    // MARK: - Document

    struct Document: Decodable {
        var version: String?
        var metadata: Metadata?
        var lines: [Line]?
        var plain: String?
    }

    struct Metadata: Decodable {
        var title: String?
        var artist: String?
        var instrumental: Bool?
    }

    struct Line: Decodable {
        var text: String?
        var startMs: Int?
        var endMs: Int?
        var words: [Word]?

        enum CodingKeys: String, CodingKey {
            case text, words
            case startMs = "start_ms"
            case endMs = "end_ms"
        }
    }

    struct Word: Decodable {
        var text: String?
        var startMs: Int?

        enum CodingKeys: String, CodingKey {
            case text
            case startMs = "start_ms"
        }
    }

    static func decode(_ yaml: String) throws -> Document {
        guard yaml.utf8.count <= maxBytes else { throw ParseError.tooLarge }

        let node: Node
        do {
            guard let composed = try Yams.compose(yaml: yaml) else { throw ParseError.invalidYAML }
            node = composed
        } catch let error as ParseError {
            throw error
        } catch {
            throw ParseError.invalidYAML
        }

        var budget = maxNodes
        guard fitsLimits(node, depth: 0, budget: &budget) else { throw ParseError.tooComplex }

        let document: Document
        do {
            document = try YAMLDecoder().decode(Document.self, from: node)
        } catch {
            throw ParseError.invalidStructure
        }
        guard document.version == "1.0" else {
            throw ParseError.unsupportedVersion(document.version)
        }
        return document
    }

    /// Walks the tree counting nodes, and stops as soon as a limit is passed.
    private static func fitsLimits(_ node: Node, depth: Int, budget: inout Int) -> Bool {
        budget -= 1
        guard budget >= 0, depth <= maxDepth else { return false }
        if let mapping = node.mapping {
            for (key, value) in mapping {
                guard fitsLimits(key, depth: depth + 1, budget: &budget),
                      fitsLimits(value, depth: depth + 1, budget: &budget) else { return false }
            }
        } else if let sequence = node.sequence {
            for item in sequence {
                guard fitsLimits(item, depth: depth + 1, budget: &budget) else { return false }
            }
        }
        return true
    }

    // MARK: - Lines

    /// Lines without `start_ms` cannot be placed in time and are skipped. A word without
    /// `start_ms` takes the time of the word before it (or of its line).
    private static func timedLine(_ line: Line) -> TimedLyricsLine? {
        guard let start = line.startMs, start >= 0 else { return nil }

        var words: [LyricsWord]?
        if let rawWords = line.words, !rawWords.isEmpty {
            var previousStart = start
            words = rawWords.compactMap { word in
                guard let text = word.text else { return nil }
                let wordStart = max(0, word.startMs ?? previousStart)
                previousStart = wordStart
                return LyricsWord(startMs: wordStart, text: text)
            }
        }

        // Per the spec, joining the words should give the line; prefer the words when the
        // line text is missing.
        let text = line.text ?? words?.map(\.text).joined() ?? ""
        return TimedLyricsLine(startMs: start, endMs: line.endMs, text: text, words: words)
    }
}
