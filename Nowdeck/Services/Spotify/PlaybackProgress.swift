import Foundation

/// Progress between two polls.
///
/// The API is polled every few seconds; in between, the position is estimated from the
/// last answer: `progress_ms` plus the time since that answer arrived, while playing. The
/// local arrival time is used instead of the answer's `timestamp`, which is Spotify's clock
/// and marks when the state last *changed*, not when it was read.
enum PlaybackProgress {
    /// Estimated position in milliseconds, between 0 and `durationMs`.
    static func interpolatedMs(
        progressMs: Int,
        durationMs: Int,
        isPlaying: Bool,
        fetchedAt: Date,
        now: Date
    ) -> Int {
        var position = progressMs
        if isPlaying {
            // A clock that moved backwards must not move the bar backwards.
            let elapsed = max(0, now.timeIntervalSince(fetchedAt))
            position += Int((elapsed * 1000).rounded(.down))
        }
        guard durationMs > 0 else { return max(0, position) }
        return min(max(0, position), durationMs)
    }

    /// Filled fraction of the bar, 0...1.
    static func fraction(positionMs: Int, durationMs: Int) -> Double {
        guard durationMs > 0 else { return 0 }
        return min(1, max(0, Double(positionMs) / Double(durationMs)))
    }

    /// The position under a finger at `x` on a bar `width` wide (dragging the progress bar).
    /// Outside the bar it stops at the start or the end.
    static func positionMs(atX x: Double, width: Double, durationMs: Int) -> Int {
        guard width > 0, durationMs > 0 else { return 0 }
        let fraction = min(1, max(0, x / width))
        return Int((fraction * Double(durationMs)).rounded())
    }

    /// Time left, `−m:ss` (or `−h:mm:ss`), with a real minus sign (U+2212) so it lines up
    /// with the digits of the monospaced font. A position past the end shows `−0:00`.
    static func remainingFormatted(positionMs: Int, durationMs: Int) -> String {
        "\u{2212}" + formatted(ms: max(0, durationMs - positionMs))
    }

    /// `m:ss`, or `h:mm:ss` from one hour (long podcast episodes).
    static func formatted(ms: Int) -> String {
        let totalSeconds = max(0, ms) / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
