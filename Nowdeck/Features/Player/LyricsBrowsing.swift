import CoreGraphics
import Foundation

/// Browsing the lyrics by dragging up and down in lyrics mode, and jumping to a stanza by
/// tapping it (owner's request, 2026-11-18).
///
/// Lyrics mode shows two stanzas, not a list, so browsing steps through them in place: every
/// `stepHeight` of vertical drag shows the next or the previous stanza in the big slot, whole
/// and with the time it starts at. Dragging up moves forward, like scrolling a list. A tap on
/// a stanza moves the playback to where it starts. After `idleTimeout` without touches the
/// lyrics follow the playback again.
enum LyricsBrowsing {
    /// Vertical drag that moves one stanza.
    static let stepHeight: CGFloat = 44
    /// Movement before a touch counts as a drag and not a tap.
    static let dragMinimumDistance: CGFloat = 10
    /// Time without touches after which browsing ends.
    static let idleTimeout: TimeInterval = 4

    /// The stanza shown after dragging `translation` points vertically from stanza `start`.
    /// Negative (up) moves to later stanzas. Stays within `0..<count`.
    static func index(from start: Int, translation: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let steps = Int((-translation / stepHeight).rounded(.towardZero))
        return min(max(0, start + steps), count - 1)
    }

    /// Where the playback has to go for `stanza` to start: its time minus the user's offset
    /// ("Sincronía de las letras", positive shows the lyrics earlier), never below zero.
    static func seekTarget(for stanza: LyricsStanza, offsetMs: Int) -> Int {
        max(0, stanza.startMs - offsetMs)
    }

    /// What lyrics mode shows while browsing: the chosen stanza whole in the big slot (as in
    /// stanza style) and the one after it below.
    static func frame(browsing index: Int, in lyrics: SyncedLyrics) -> LyricsFrame? {
        guard lyrics.stanzas.indices.contains(index) else { return nil }
        return LyricsFrame(primaryIndex: index, isPrimaryActive: true,
                           nextIndex: index + 1 < lyrics.stanzas.count ? index + 1 : nil,
                           sungWordCount: lyrics.stanzas[index].words.count)
    }

    /// The stanza a drag starts from when not browsing yet: the one in the big slot, or the
    /// last one once the lyrics are over.
    static func startIndex(for lyrics: SyncedLyrics, atMs position: Int) -> Int {
        LyricsTimeline.frame(for: lyrics, atMs: position)?.primaryIndex
            ?? max(0, lyrics.stanzas.count - 1)
    }
}
