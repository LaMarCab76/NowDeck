import Foundation

/// What lyrics mode shows at a given playback position.
struct LyricsFrame: Equatable, Sendable {
    /// The stanza in the big slot (30 pt).
    let primaryIndex: Int
    /// Whether that stanza is being sung. `false` before the first line and during an
    /// instrumental break: then the upcoming stanza waits in the big slot, all in
    /// `letraPendiente`.
    let isPrimaryActive: Bool
    /// The stanza in the small slot (22 pt), if any.
    let nextIndex: Int?
    /// Words of the primary stanza already sung (word sync only; line sync shows the whole
    /// stanza at once).
    let sungWordCount: Int
}

/// Finds the current and next stanza for a playback position (docs/04-letras.md):
/// current = the stanza that holds the last line starting at or before the position;
/// next = the one after it.
enum LyricsTimeline {
    /// `nil` when there is nothing to show (no stanzas, or the last stanza already ended).
    static func frame(for lyrics: SyncedLyrics, atMs position: Int) -> LyricsFrame? {
        let stanzas = lyrics.stanzas
        guard !stanzas.isEmpty else { return nil }

        guard let current = currentStanzaIndex(in: stanzas, atMs: position) else {
            // Before the first line: show the first stanza as upcoming.
            return LyricsFrame(primaryIndex: 0, isPrimaryActive: false,
                               nextIndex: stanzas.count > 1 ? 1 : nil, sungWordCount: 0)
        }

        if let end = stanzas[current].endMs, position >= end {
            // Instrumental break after the stanza: the next one waits in the big slot.
            let upcoming = current + 1
            guard upcoming < stanzas.count else { return nil }
            return LyricsFrame(primaryIndex: upcoming, isPrimaryActive: false,
                               nextIndex: upcoming + 1 < stanzas.count ? upcoming + 1 : nil,
                               sungWordCount: 0)
        }

        let sung: Int
        switch lyrics.sync {
        // Words are highlighted as a prefix, so the sung part is always one piece of text.
        case .word: sung = stanzas[current].words.prefix { $0.startMs <= position }.count
        case .line: sung = stanzas[current].words.count
        }
        return LyricsFrame(primaryIndex: current, isPrimaryActive: true,
                           nextIndex: current + 1 < stanzas.count ? current + 1 : nil,
                           sungWordCount: sung)
    }

    /// Index of the stanza with the last line whose start is ≤ `position`. Stanzas are in
    /// time order, so it is the last stanza that has started.
    static func currentStanzaIndex(in stanzas: [LyricsStanza], atMs position: Int) -> Int? {
        stanzas.lastIndex { $0.startMs <= position }
    }
}
