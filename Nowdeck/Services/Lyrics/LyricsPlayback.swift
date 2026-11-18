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

    /// Position used to pick the stanza: `positionMs(at:)` moved by the user's offset
    /// ("Sincronía de las letras"). Positive shows the lyrics earlier. Never below zero.
    func lyricsPositionMs(at date: Date, offsetMs: Int) -> Int {
        max(0, positionMs(at: date) + offsetMs)
    }

    /// The snapshot to keep after a new poll.
    ///
    /// Small differences are poll jitter and are ignored, so the lyrics do not jump back and
    /// forth; a jump of more than 1.5 s, or a play/pause change, takes the new snapshot.
    ///
    /// While paused nothing is interpolated, so there is no jitter to filter: any other
    /// position is real (a seek, or a failed seek put back) and is taken at once.
    func reconciled(with polled: LyricsPlayback) -> LyricsPlayback {
        if polled.isPlaying != isPlaying { return polled }
        if !isPlaying { return polled.progressMs == progressMs ? self : polled }
        let interpolated = positionMs(at: polled.timestamp)
        if abs(polled.progressMs - interpolated) > Self.resyncThresholdMs { return polled }
        return self
    }
}
