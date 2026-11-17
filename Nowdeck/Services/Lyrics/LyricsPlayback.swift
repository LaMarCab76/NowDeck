import Foundation

/// The playback position as the player last saw it, to interpolate between polls.
///
/// The player (milestone 2) builds one from each `GET /me/player` answer: `progress_ms`,
/// `is_playing` and the moment the answer arrived.
struct LyricsPlayback: Equatable, Sendable {
    var progressMs: Int
    var isPlaying: Bool
    /// When `progressMs` was measured.
    var timestamp: Date

    /// If a poll differs from the interpolated position by more than this, someone moved the
    /// playback (seek) and lyrics resynchronize (docs/04-letras.md).
    static let resyncThresholdMs = 1_500

    /// Position at `date`: `progress_ms` plus the time elapsed while playing.
    func positionMs(at date: Date) -> Int {
        guard isPlaying else { return progressMs }
        let elapsed = max(0, date.timeIntervalSince(timestamp))
        return progressMs + Int((elapsed * 1000).rounded())
    }

    /// The snapshot to keep after a new poll.
    ///
    /// Small differences are poll jitter and are ignored, so the lyrics do not jump back and
    /// forth; a jump of more than 1.5 s, or a play/pause change, takes the new snapshot.
    func reconciled(with polled: LyricsPlayback) -> LyricsPlayback {
        if polled.isPlaying != isPlaying { return polled }
        let interpolated = positionMs(at: polled.timestamp)
        if abs(polled.progressMs - interpolated) > Self.resyncThresholdMs { return polled }
        return self
    }
}
