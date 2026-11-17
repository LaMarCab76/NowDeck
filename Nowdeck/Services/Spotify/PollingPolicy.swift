import Foundation

/// How long to wait before the next `GET /me/player` (docs/03-spotify-api.md, "Polling").
///
/// The Web API has no push notifications, so the app polls: often while music plays (the
/// title can change at any moment), less while paused, and backing off after errors.
struct PollingPolicy: Equatable, Sendable {
    /// What the last poll found.
    enum Outcome: Equatable, Sendable {
        case playing
        /// Paused, or nothing playing.
        case idle
        /// `403`: nothing will change until the user fixes their app settings.
        case forbidden
        case rateLimited(retryAfter: TimeInterval)
        /// Server error or no connection.
        case failed
    }

    var playingInterval: TimeInterval = 3
    var idleInterval: TimeInterval = 10
    /// After a `QUOTA_EXCEEDED`, poll less for a while (`quotaCooldown`).
    var quotaPlayingInterval: TimeInterval = 10
    var quotaIdleInterval: TimeInterval = 30
    var quotaCooldown: TimeInterval = 15 * 60
    var forbiddenInterval: TimeInterval = 30
    /// First wait after a failure; it doubles with each consecutive failure.
    var firstBackoff: TimeInterval = 3
    var maxBackoff: TimeInterval = 60
    /// Upper bound for a `Retry-After`. Spotify can send very long ones; the client keeps
    /// refusing calls until it passes, so waking up earlier costs no request.
    var maxRetryAfter: TimeInterval = 10 * 60

    /// - Parameters:
    ///   - consecutiveFailures: failures in a row, including this one (for `.failed`).
    ///   - quotaLimited: a `QUOTA_EXCEEDED` happened less than `quotaCooldown` ago.
    ///   - jitter: a small random amount added to waits after errors.
    func delay(after outcome: Outcome, consecutiveFailures: Int = 0, quotaLimited: Bool = false,
               jitter: TimeInterval = 0) -> TimeInterval {
        switch outcome {
        case .playing:
            return quotaLimited ? quotaPlayingInterval : playingInterval
        case .idle:
            return quotaLimited ? quotaIdleInterval : idleInterval
        case .forbidden:
            return forbiddenInterval
        case .rateLimited(let retryAfter):
            return min(maxRetryAfter, max(0, retryAfter)) + jitter
        case .failed:
            let exponent = max(0, consecutiveFailures - 1)
            let backoff = firstBackoff * pow(2, Double(min(exponent, 10)))
            return min(maxBackoff, backoff) + jitter
        }
    }
}
