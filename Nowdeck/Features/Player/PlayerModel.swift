import UIKit

/// State of the player screen, kept up to date by polling `GET /me/player`.
///
/// - `start()` / `stop()` follow the scene phase: no polling in the background.
/// - Every poll's answer replaces `playback`; between polls the view interpolates the
///   progress from `fetchedAt` (`PlaybackProgress`).
/// - After an error the last state stays on screen and `freshness` says it may be old.
///
/// Commands (milestone 3) live in `PlayerControlsModel` (`controls`). While one is in flight
/// they hold the polling (`holdPolling()`), change `playback` optimistically
/// (`updatePlayback(_:)`) and poll again shortly after (`resumePolling(after:)`).
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
    /// Photo of the track's first artist, shown behind the player (`PlayerBackgroundView`).
    /// `nil` for episodes, ads, artists without photos, or with the option off.
    @Published private(set) var artistImage: UIImage?
    @Published private(set) var freshness: Freshness = .live

    /// The first item of Spotify's queue, shown when swiping from the right edge.
    /// `nil` while unknown (not read yet, empty queue, or the read failed).
    @Published private(set) var upNext: TrackPreview?
    /// The item that played before, from what this app saw (the Web API has no "previous
    /// item"). Shown when swiping from the left edge. `nil` right after opening the app.
    @Published private(set) var previousTrack: TrackPreview?

    /// Commands and the volume panel. Created on first use, so that it shares this model;
    /// it keeps only a weak reference back.
    private(set) lazy var controls = PlayerControlsModel(player: self)

    /// Shared with `controls` (playback commands) and the sheets that call the API on their
    /// own (Dispositivos, Biblioteca).
    let api: SpotifyAPI
    private let artworkLoader: ArtworkLoader
    private let policy: PollingPolicy
    private let now: () -> Date

    private var pollTask: Task<Void, Never>?
    /// Between `start()` and `stop()`: the screen is visible and the app in the foreground.
    private var wantsPolling = false
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

    /// Covers already downloaded for the swipe previews (next and previous items). When one of
    /// them starts playing, its cover appears at once instead of loading again.
    private var preloadedArtwork: [URL: ArtworkLoader.Artwork] = [:]
    private var preloadedOrder: [URL] = []
    private static let preloadedLimit = 6

    /// The items that played before the current one, newest last.
    private var history: [TrackPreview] = []
    private static let historyLimit = 20

    private var upNextTask: Task<Void, Never>?
    private var upNextFetchedAt: Date?
    /// The queue is read again when a swipe starts and the last read is older than this:
    /// the user may have queued something in Spotify meanwhile.
    static let upNextMaxAge: TimeInterval = 15

    /// Ajustes → Apariencia → "Foto del artista". Off: no `GET /artists/{id}` at all.
    var loadsArtistImages = true {
        didSet {
            guard loadsArtistImages != oldValue else { return }
            artistImageKey = nil
            artistImageTask?.cancel()
            artistImage = nil
            if loadsArtistImages { updateArtistImage(nowPlaying) }
        }
    }

    private enum ArtistPhotoLookup {
        /// The widest photo, or `nil` when the artist has none.
        case found(URL?)
        /// `403`/`404`: don't ask again for this artist.
        case unavailable
        /// Temporary failure; try again after this date.
        case retry(after: Date)
    }
    /// One `GET /artists/{id}` per artist while the app runs.
    private var artistPhotos: [String: ArtistPhotoLookup] = [:]
    /// The artist whose photo is on screen or on its way.
    private var artistImageKey: String?
    private var artistImageTask: Task<Void, Never>?

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
        wantsPolling = true
        guard pollTask == nil else { return }
        schedule(initialDelay: 0)
    }

    func stop() {
        wantsPolling = false
        pollTask?.cancel()
        pollTask = nil
    }

    /// Pauses the polling while a command is in flight, so that an answer read *before* the
    /// command cannot overwrite the optimistic state. Cancelling also drops a poll that is
    /// already waiting for its answer.
    func holdPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Polls again after `delay` and continues the cycle, unless the screen stopped polling
    /// meanwhile (background).
    func resumePolling(after delay: TimeInterval) {
        guard wantsPolling else { return }
        holdPolling()
        schedule(initialDelay: delay)
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
            // Held for a command while the answer was on its way: it may predate the command.
            try Task.checkCancellation()
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
        updateArtistImage(nil)
        upNextTask?.cancel()
        upNext = nil
        upNextFetchedAt = nil
        freshness = .live
    }

    // MARK: Local changes (commands)

    /// Changes the state on screen before Spotify confirms a command (optimistic update), or
    /// takes such a change back. The progress is first moved to the position interpolated
    /// for this instant, so pausing freezes the bar where it is and playing continues from
    /// there.
    func updatePlayback(_ change: (inout PlaybackState) -> Void) {
        guard status == .active, var state = playback else { return }
        let date = now()
        if let progress = state.progressMs, let durationMs = nowPlaying?.durationMs {
            state.progressMs = PlaybackProgress.interpolatedMs(
                progressMs: progress, durationMs: durationMs, isPlaying: state.isPlaying,
                fetchedAt: fetchedAt, now: date)
        }
        change(&state)
        playback = state
        fetchedAt = date
    }

    /// The progress shown right now, in milliseconds.
    var currentPositionMs: Int? {
        guard let playback, let progress = playback.progressMs,
              let durationMs = nowPlaying?.durationMs else { return nil }
        return PlaybackProgress.interpolatedMs(progressMs: progress, durationMs: durationMs,
                                               isPlaying: playback.isPlaying,
                                               fetchedAt: fetchedAt, now: now())
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
        if nowPlaying != item {
            if let previous = nowPlaying, previous.transitionKey != item.transitionKey {
                itemDidChange(from: previous, to: item)
            } else if nowPlaying == nil {
                refreshUpNext()
            }
            nowPlaying = item
        }
        status = .active

        let newOrigin = resolvedOrigin(for: state)
        if origin != newOrigin { origin = newOrigin }
        updateArtwork(item)
        updateArtistImage(item)
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
        if let preloaded = preloadedArtwork[url] {
            artwork = preloaded.image
            artworkColor = preloaded.dominantColor
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

    // MARK: Swipe previews

    /// Another item started: the one that ended goes to the history, unless the user went
    /// back to the item on top of it (then that one leaves the history).
    private func itemDidChange(from previous: NowPlaying, to item: NowPlaying) {
        if history.last?.item.transitionKey == item.transitionKey {
            history.removeLast()
        } else if !previous.isAd {
            if let url = previous.artworkURL, let artwork {
                remember(ArtworkLoader.Artwork(image: artwork, dominantColor: artworkColor),
                         for: url)
            }
            history.append(TrackPreview(item: previous, artwork: artwork))
            if history.count > Self.historyLimit { history.removeFirst() }
        }
        previousTrack = history.last
        refreshUpNext()
    }

    /// Reads the queue again if the last read is older than `upNextMaxAge`. Called when a
    /// swipe from the right edge starts.
    func refreshUpNextIfStale() {
        guard status == .active, upNextTask == nil else { return }
        if let upNextFetchedAt, now().timeIntervalSince(upNextFetchedAt) < Self.upNextMaxAge {
            return
        }
        refreshUpNext()
    }

    /// One `GET /me/player/queue` and the cover of its first item. A failure only leaves the
    /// preview empty: the swipe still works, with a generic card.
    private func refreshUpNext() {
        upNextTask?.cancel()
        upNextTask = Task { [weak self, api, artworkLoader] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.upNextTask = nil } }
            let next: NowPlaying?
            do {
                let queue = try await api.playbackQueue()
                next = queue.queue.lazy.compactMap(NowPlaying.init(item:)).first
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.upNext = nil
                self.upNextFetchedAt = nil
                return
            }
            guard !Task.isCancelled else { return }
            self.upNextFetchedAt = self.now()
            guard let next else {
                self.upNext = nil
                return
            }
            // The title right away; the cover when it arrives.
            let cached = next.artworkURL.flatMap { self.preloadedArtwork[$0] }
            self.upNext = TrackPreview(item: next, artwork: cached?.image)
            guard cached == nil, let url = next.artworkURL else { return }
            guard let loaded = try? await artworkLoader.load(url, cacheKey: next.artworkCacheKey),
                  !Task.isCancelled
            else { return }
            self.remember(loaded, for: url)
            if self.upNext?.item == next {
                self.upNext = TrackPreview(item: next, artwork: loaded.image)
            }
        }
    }

    private func remember(_ artwork: ArtworkLoader.Artwork, for url: URL) {
        if preloadedArtwork[url] == nil {
            preloadedOrder.append(url)
        }
        preloadedArtwork[url] = artwork
        if preloadedOrder.count > Self.preloadedLimit {
            preloadedArtwork[preloadedOrder.removeFirst()] = nil
        }
    }

    // MARK: Artist photo

    /// Fetches the photo of the item's first artist when the artist changes. Tracks of the
    /// same artist keep the photo on screen without asking again.
    private func updateArtistImage(_ item: NowPlaying?) {
        let artistID = loadsArtistImages ? item?.artistID : nil
        guard artistID != artistImageKey else { return }
        artistImageKey = artistID
        artistImageTask?.cancel()

        guard let artistID else {
            artistImage = nil
            return
        }
        // The previous artist's photo stays until the new one is ready: one cross-fade.
        artistImageTask = Task { [weak self, api, artworkLoader] in
            guard let self else { return }
            let photoURL: URL?
            /// A temporary failure: the next polls look again, until `retry(after:)` passes.
            var retriesLater = false
            switch self.artistPhotos[artistID] {
            case .found(let url):
                photoURL = url
            case .unavailable:
                photoURL = nil
            case .retry(let after) where self.now() < after:
                photoURL = nil
                retriesLater = true
            case .retry, nil:
                do {
                    let url = NowPlaying.bestImage(try await api.artistImages(id: artistID))
                    self.artistPhotos[artistID] = .found(url)
                    photoURL = url
                } catch is CancellationError {
                    return
                } catch SpotifyAPIError.forbidden, SpotifyAPIError.notFound {
                    self.artistPhotos[artistID] = .unavailable
                    photoURL = nil
                } catch {
                    self.artistPhotos[artistID] = .retry(after: self.now().addingTimeInterval(60))
                    photoURL = nil
                    retriesLater = true
                }
            }
            guard !Task.isCancelled, self.artistImageKey == artistID else { return }
            guard let photoURL else {
                self.artistImage = nil
                if retriesLater { self.artistImageKey = nil }
                return
            }
            do {
                let image = try await artworkLoader.loadImage(photoURL)
                guard !Task.isCancelled, self.artistImageKey == artistID else { return }
                self.artistImage = image
            } catch {
                guard self.artistImageKey == artistID else { return }
                self.artistImage = nil
            }
        }
    }
}

/// What the swipe shows of the next or previous item: the same cover and title as the player.
struct TrackPreview: Equatable {
    var item: NowPlaying
    var artwork: UIImage?

    static func == (lhs: TrackPreview, rhs: TrackPreview) -> Bool {
        lhs.item == rhs.item && lhs.artwork === rhs.artwork
    }
}
