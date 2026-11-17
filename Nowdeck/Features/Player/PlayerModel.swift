import UIKit

/// State of the player screen, kept up to date by polling `GET /me/player`.
///
/// - `start()` / `stop()` follow the scene phase: no polling in the background.
/// - Every poll's answer replaces `playback`; between polls the view interpolates the
///   progress from `fetchedAt` (`PlaybackProgress`).
/// - After an error the last state stays on screen and `freshness` says it may be old.
///
/// Milestone 3 adds the commands; after each one it should update `playback` optimistically
/// and call `refresh(after: 0.6)` to confirm.
@MainActor
final class PlayerModel: ObservableObject {
    enum Status: Equatable {
        /// Before the first answer.
        case loading
        /// `204`, or an answer without anything to show.
        case nothingPlaying
        case active
        /// `403`: the account cannot use this app (see `SpotifyAPIError.forbidden`).
        case accessDenied
        /// The first poll failed (no connection, server errors). Retries on its own.
        case unavailable
    }

    enum Freshness: Equatable {
        case live
        /// The last poll failed: what is on screen may be old.
        case stale
        /// Spotify answered `429 QUOTA_EXCEEDED`: polling slowed down for a while.
        case quotaLimited
    }

    @Published private(set) var status: Status = .loading
    @Published private(set) var playback: PlaybackState?
    @Published private(set) var nowPlaying: NowPlaying?
    /// Local time when `playback` arrived. Base for the progress interpolation.
    @Published private(set) var fetchedAt = Date.distantPast
    @Published private(set) var origin: PlaybackOrigin?
    @Published private(set) var artwork: UIImage?
    /// Dominant color of the artwork; the view softens it with the theme
    /// (`ArtworkColor.playerBackground`). `nil` = theme background.
    @Published private(set) var artworkColor: RGBColor?
    @Published private(set) var freshness: Freshness = .live

    let api: SpotifyAPI
    private let artworkLoader: ArtworkLoader
    private let policy: PollingPolicy
    private let now: () -> Date

    private var pollTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var quotaLimitedUntil: Date?

    private enum NameLookup {
        case found(String)
        /// `403`/`404`: the app may not read this playlist (for example Spotify's own
        /// editorial playlists). Show the type only and don't ask again.
        case unavailable
        case inFlight
        /// Temporary failure; try again after this date.
        case retry(after: Date)
    }
    private var playlistNames: [String: NameLookup] = [:]

    private var artworkURL: URL?
    private var artworkTask: Task<Void, Never>?

    init(api: SpotifyAPI, artworkLoader: ArtworkLoader = ArtworkLoader(),
         policy: PollingPolicy = PollingPolicy(), now: @escaping () -> Date = { Date() }) {
        self.api = api
        self.artworkLoader = artworkLoader
        self.policy = policy
        self.now = now
    }

    // MARK: Polling

    /// Starts polling right away. Does nothing if it is already running.
    func start() {
        guard pollTask == nil else { return }
        schedule(initialDelay: 0)
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Polls again after `delay` seconds and continues the regular cycle from there.
    func refresh(after delay: TimeInterval = 0) {
        stop()
        schedule(initialDelay: delay)
    }

    private func schedule(initialDelay: TimeInterval) {
        pollTask = Task { [weak self] in
            var delay = initialDelay
            while !Task.isCancelled {
                if delay > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    } catch {
                        return // cancelled
                    }
                }
                guard let self else { return }
                delay = await self.poll()
            }
        }
    }

    /// One poll. Returns how long to wait before the next one.
    @discardableResult
    func poll() async -> TimeInterval {
        do {
            let state = try await api.playbackState()
            consecutiveFailures = 0
            apply(state, at: now())
            let quotaLimited = isQuotaLimited
            freshness = quotaLimited ? .quotaLimited : .live
            let outcome: PollingPolicy.Outcome = state?.isPlaying == true ? .playing : .idle
            return policy.delay(after: outcome, quotaLimited: quotaLimited)

        } catch is CancellationError {
            return 0

        } catch SpotifyAPIError.forbidden {
            showOnly(.accessDenied)
            return policy.delay(after: .forbidden)

        } catch SpotifyAPIError.notFound {
            // "No active device" on some accounts: same as nothing playing.
            apply(nil, at: now())
            return policy.delay(after: .idle, quotaLimited: isQuotaLimited)

        } catch let SpotifyAPIError.rateLimited(retryAfter, quotaExceeded) {
            if quotaExceeded {
                quotaLimitedUntil = now().addingTimeInterval(policy.quotaCooldown)
            }
            markFailure(quotaExceeded: quotaExceeded)
            return policy.delay(after: .rateLimited(retryAfter: retryAfter),
                                jitter: Double.random(in: 0...1))

        } catch {
            consecutiveFailures += 1
            markFailure(quotaExceeded: false)
            return policy.delay(after: .failed, consecutiveFailures: consecutiveFailures,
                                jitter: Double.random(in: 0...0.5))
        }
    }

    private var isQuotaLimited: Bool {
        guard let quotaLimitedUntil else { return false }
        return now() < quotaLimitedUntil
    }

    /// Keeps the last state on screen and marks it as possibly old.
    private func markFailure(quotaExceeded: Bool) {
        switch status {
        case .loading, .unavailable:
            status = .unavailable
        case .active, .nothingPlaying, .accessDenied:
            break
        }
        freshness = (quotaExceeded || isQuotaLimited) ? .quotaLimited : .stale
    }

    private func showOnly(_ newStatus: Status) {
        status = newStatus
        playback = nil
        nowPlaying = nil
        origin = nil
        updateArtwork(nil)
        freshness = .live
    }

    // MARK: Applying an answer

    private func apply(_ state: PlaybackState?, at date: Date) {
        guard let state, let item = NowPlaying(state: state) else {
            showOnly(.nothingPlaying)
            playback = state
            fetchedAt = date
            return
        }
        playback = state
        fetchedAt = date
        if nowPlaying != item { nowPlaying = item }
        status = .active

        let newOrigin = resolvedOrigin(for: state)
        if origin != newOrigin { origin = newOrigin }
        updateArtwork(item)
    }

    /// The origin with its name filled from the cache, starting a lookup if needed.
    private func resolvedOrigin(for state: PlaybackState) -> PlaybackOrigin? {
        guard var origin = PlaybackOrigin.from(context: state.context, item: state.item) else {
            return nil
        }
        guard let playlistID = origin.playlistID else { return origin }

        switch playlistNames[playlistID] {
        case .found(let name):
            origin.name = name
        case .unavailable, .inFlight:
            break
        case .retry(let after) where now() < after:
            break
        case .retry, nil:
            lookUpPlaylistName(playlistID)
        }
        return origin
    }

    private func lookUpPlaylistName(_ playlistID: String) {
        playlistNames[playlistID] = .inFlight
        Task { [weak self, api] in
            let result: NameLookup
            do {
                result = .found(try await api.playlistName(id: playlistID))
            } catch SpotifyAPIError.forbidden, SpotifyAPIError.notFound {
                result = .unavailable
            } catch {
                result = .retry(after: Date().addingTimeInterval(60))
            }
            guard let self else { return }
            self.playlistNames[playlistID] = result
            if case .found(let name) = result, self.origin?.playlistID == playlistID {
                self.origin?.name = name
            }
        }
    }

    // MARK: Artwork

    private func updateArtwork(_ item: NowPlaying?) {
        let url = item?.artworkURL
        guard url != artworkURL else { return }
        artworkURL = url
        artworkTask?.cancel()
        // Never show the previous cover next to the new title. The background color stays
        // until the new one is ready, so it changes in one smooth transition.
        artwork = nil

        guard let url else {
            artworkColor = nil
            return
        }
        let cacheKey = item?.artworkCacheKey
        artworkTask = Task { [weak self, artworkLoader] in
            do {
                let loaded = try await artworkLoader.load(url, cacheKey: cacheKey)
                guard let self, self.artworkURL == url else { return }
                self.artwork = loaded.image
                self.artworkColor = loaded.dominantColor
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.artworkURL == url else { return }
                self.artworkColor = nil
                if case ArtworkLoader.LoadError.network = error {
                    // Try again on the next poll.
                    self.artworkURL = nil
                }
            }
        }
    }
}
