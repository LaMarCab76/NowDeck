import Foundation

/// The result of looking up lyrics for a track.
enum LyricsLookup: Equatable, Sendable {
    case found(SyncedLyrics)
    /// LRCLIB has no synced lyrics for the track (404, plain text only or instrumental).
    case notFound
    /// The lookup could not be done (no connection, LRCLIB busy). Not cached: a later tap
    /// tries again.
    case failed
}

/// Something that finds lyrics for a track. `LyricsService` is the real one; tests and
/// previews use fakes.
protocol LyricsProviding: Sendable {
    func lyrics(for track: LyricsTrack) async -> LyricsLookup
}

/// Finds lyrics: cache first, then LRCLIB, honoring its rate limit.
///
/// Rate limit (https://lrclib.net/docs, "Rate Limiting"): after a `429` or `503`, no request
/// is sent until `Retry-After` (plus up to 30 % random jitter) has passed. A user waiting for
/// lyrics gets one automatic retry if the wait is short (≤ 5 s); otherwise the lookup fails
/// and the next tap tries again.
actor LyricsService: LyricsProviding {
    static let maxAutomaticRetryWait: TimeInterval = 5
    static let maxJitter = 0.3

    private let client: LRCLIBClient
    private let cache: LyricsCache
    private let now: @Sendable () -> Date
    private let jitter: @Sendable () -> Double
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// No request goes to LRCLIB before this date.
    private var blockedUntil: Date?

    init(
        client: LRCLIBClient = LRCLIBClient(),
        cache: LyricsCache = LyricsCache(),
        now: @escaping @Sendable () -> Date = Date.init,
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...LyricsService.maxJitter) },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.client = client
        self.cache = cache
        self.now = now
        self.jitter = jitter
        self.sleep = sleep
    }

    func lyrics(for track: LyricsTrack) async -> LyricsLookup {
        if let id = track.spotifyID {
            switch await cache.lookup(spotifyID: id) {
            case .found(let record): return Self.lookup(from: record)
            case .notFound: return .notFound
            case .miss: break
            }
        }

        do {
            let record = try await fetchHonoringRateLimit(track, retriesLeft: 1)
            if let id = track.spotifyID {
                await cache.store(record, forSpotifyID: id)
            }
            return record.map(Self.lookup(from:)) ?? .notFound
        } catch {
            return .failed
        }
    }

    private static func lookup(from record: LRCLIBRecord) -> LyricsLookup {
        record.syncedLyricsForDisplay().map(LyricsLookup.found) ?? .notFound
    }

    /// At most `1 + retriesLeft` requests reach LRCLIB.
    private func fetchHonoringRateLimit(_ track: LyricsTrack, retriesLeft: Int) async throws -> LRCLIBRecord? {
        if let blockedUntil {
            let wait = blockedUntil.timeIntervalSince(now())
            if wait > Self.maxAutomaticRetryWait {
                throw LRCLIBError.rateLimited(retryAfter: wait)
            }
            if wait > 0 {
                try await sleep(wait)
            }
        }

        do {
            return try await client.lyrics(for: track)
        } catch LRCLIBError.rateLimited(let retryAfter) {
            blockedUntil = now().addingTimeInterval(retryAfter * (1 + jitter()))
            guard retriesLeft > 0 else { throw LRCLIBError.rateLimited(retryAfter: retryAfter) }
            return try await fetchHonoringRateLimit(track, retriesLeft: retriesLeft - 1)
        }
    }
}
