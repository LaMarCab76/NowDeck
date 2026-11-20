import SwiftUI

/// One row of the queue: the same track data as the playlist detail, plus a small cover.
struct QueueEntry: Identifiable, Equatable, Sendable {
    var track: CollectionTrack
    var artworkURL: URL?
    /// The `spotify:track:` URI that a tap plays, or `nil` when the row cannot be played
    /// from here: episodes (`uris` is documented for tracks only, and shows are not a valid
    /// `context_uri`) and local files.
    var playURI: String? = nil

    /// The position in the queue: the same track can be queued twice.
    var id: Int { track.id }
}

extension QueueEntry {
    /// The rows for a queue answer: at most `Metrics.Queue.maxItems`, skipping item types
    /// the app does not know and items without a name. Numbers stay consecutive.
    static func entries(from queue: PlaybackQueue,
                        limit: Int = Metrics.Queue.maxItems) -> [QueueEntry] {
        var entries: [QueueEntry] = []
        for item in queue.queue {
            guard entries.count < limit else { break }
            if let entry = QueueEntry(item: item, position: entries.count) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// `nil` for unknown item types and for items without a name.
    init?(item: PlaybackItem, position: Int) {
        switch item {
        case .track(let track):
            guard !track.name.isEmpty else { return nil }
            self.init(
                track: CollectionTrack(
                    id: position,
                    number: position + 1,
                    title: track.name,
                    subtitle: track.artists.map(\.name).filter { !$0.isEmpty }
                        .joined(separator: ", "),
                    durationMs: track.durationMs,
                    isExplicit: track.explicit,
                    // Local files cannot be opened in Spotify; they are dimmed like in the
                    // playlist detail.
                    isAvailable: !track.isLocal,
                    pageURL: track.isLocal ? nil
                        : NowPlaying.pageURL(externalURL: track.externalUrls?.spotify,
                                             uri: track.uri)
                ),
                artworkURL: Self.thumbnail(track.album?.images ?? []),
                playURI: track.isLocal ? nil : track.uri.flatMap(Self.trackURI)
            )

        case .episode(let episode):
            guard !episode.name.isEmpty else { return nil }
            self.init(
                track: CollectionTrack(
                    id: position,
                    number: position + 1,
                    title: episode.name,
                    subtitle: episode.show?.name ?? "",
                    durationMs: episode.durationMs,
                    isExplicit: episode.explicit,
                    isAvailable: true,
                    pageURL: NowPlaying.pageURL(externalURL: episode.externalUrls?.spotify,
                                                uri: episode.uri)
                ),
                artworkURL: Self.thumbnail(episode.images.isEmpty
                                           ? (episode.show?.images ?? []) : episode.images)
            )

        case .unsupported:
            return nil
        }
    }

    /// `uri` when it is a track URI (`spotify:track:<id>`).
    static func trackURI(_ uri: String) -> String? {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "spotify", parts[1] == "track",
              !parts[2].isEmpty else { return nil }
        return uri
    }

    /// The smallest image that is still sharp at 40 pt on a 3× screen (120 px): Spotify
    /// sends 640, 300 and 64 px, so this picks the 300 one. Without sizes, the first image.
    static func thumbnail(_ images: [SpotifyImage], minimumWidth: Int = 120) -> URL? {
        let usable = images.filter { URL(string: $0.url)?.scheme == "https" }
        let sharpEnough = usable.filter { ($0.width ?? 0) >= minimumWidth }
        let best = sharpEnough.min { ($0.width ?? 0) < ($1.width ?? 0) }
            ?? usable.max { ($0.width ?? 0) < ($1.width ?? 0) }
        return best.flatMap { URL(string: $0.url) }
    }
}

/// Why the queue could not be read. Same cases and wording as Dispositivos
/// (`DevicesProblem`), without the transfer-only one.
enum QueueProblem: Equatable {
    /// `403`: no Premium, or the user is not in *Users Management* (docs/03).
    case forbidden
    /// `429`. The API client already waits `Retry-After` before calling again.
    case rateLimited
    /// No connection, timeouts or `5xx`.
    case connection
    case unknown
    /// Playing a tapped track: `404`, there is no active device.
    case noActiveDevice
    /// Playing a tapped track failed for another reason.
    case playbackFailed

    init(_ error: Error) {
        switch error {
        case SpotifyAPIError.forbidden: self = .forbidden
        case SpotifyAPIError.rateLimited: self = .rateLimited
        case SpotifyAPIError.network, SpotifyAPIError.server: self = .connection
        default: self = .unknown
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .forbidden:
            return "Spotify rechazó el pedido. Revisá que tu cuenta tenga Premium y siga en Users Management de tu app."
        case .rateLimited:
            return "Spotify pide esperar un momento. Probá de nuevo en unos segundos."
        case .connection:
            return "No hay conexión con Spotify. Revisá internet y probá de nuevo."
        case .unknown:
            return "Algo salió mal. Probá de nuevo."
        case .noActiveDevice:
            return "No hay un dispositivo activo. Elegí uno para escuchar."
        case .playbackFailed:
            return "No pudimos reproducirlo. Probá de nuevo."
        }
    }

    /// The problem for a failed `playFromQueue`. A `404` there means no active device.
    init(playing error: Error) {
        switch error {
        case SpotifyAPIError.notFound: self = .noActiveDevice
        case SpotifyAPIError.forbidden: self = .forbidden
        case SpotifyAPIError.rateLimited: self = .rateLimited
        case SpotifyAPIError.network: self = .connection
        default: self = .playbackFailed
        }
    }
}

/// State of the player's queue.
///
/// The queue is read when Queue opens, when the player shows another track while
/// Queue is open and on pull to refresh. It is **not** polled: the
/// player's polling already spends the request quota (docs/03, "Polling y estado local").
@MainActor
final class QueueModel: ObservableObject {
    /// `nil` until the first answer arrives.
    @Published private(set) var entries: [QueueEntry]?
    @Published private var readProblem: QueueProblem?
    @Published private var playbackProblem: QueueProblem?
    /// An automatic read can fix a loading error while a playback failure still needs to
    /// be shown when the user returns to Queue.
    var problem: QueueProblem? { playbackProblem ?? readProblem }
    @Published private(set) var isLoading = false
    /// The row whose track is starting, while its request runs. Other taps wait for it.
    @Published private(set) var startingID: QueueEntry.ID?

    private let api: SpotifyAPI
    /// The only worker that reads the queue. Reads never overlap, so an older answer can
    /// never land after a newer one.
    private var loadTask: Task<Void, Never>?
    private var playbackGeneration = 0
    /// The newest playback generation a caller requested. An invalidation alone does not
    /// request a read while Queue is closed.
    private var requestedGeneration = 0
    /// Reload calls waiting for the worker. Only read by tests.
    private(set) var waitingCalls = 0

    init(api: SpotifyAPI) {
        self.api = api
    }

    /// Discard later answers for the old playback, even when the queue view is absent.
    func invalidateForPlaybackChange() {
        playbackGeneration += 1
    }

    /// Reloads for the current playback. Readers share a request unless playback changed
    /// after it started, in which case the worker reads again before returning.
    func reload(clearingPlaybackProblem: Bool = false) async {
        if clearingPlaybackProblem { playbackProblem = nil }
        requestedGeneration = playbackGeneration
        waitingCalls += 1
        defer { waitingCalls -= 1 }
        await worker().value
    }

    private func worker() -> Task<Void, Never> {
        if let loadTask { return loadTask }
        let task = Task {
            var generation: Int
            repeat {
                generation = playbackGeneration
                await fetch(generation: generation)
            } while generation < requestedGeneration
            loadTask = nil
        }
        loadTask = task
        return task
    }

    /// Plays a tapped row (after the confirmation) and returns whether Spotify accepted it.
    /// The queue is not read here: the new track changes the player's `itemStarts`, and
    /// the view reads the queue then. A failure is shown above the list.
    func play(_ entry: QueueEntry, context: PlaybackContext?) async -> Bool {
        guard let uri = entry.playURI, startingID == nil else { return false }
        startingID = entry.id
        playbackProblem = nil
        defer { startingID = nil }
        do {
            try await api.playFromQueue(trackURI: uri, context: context)
            return true
        } catch is CancellationError {
            return false
        } catch {
            playbackProblem = QueueProblem(playing: error)
            return false
        }
    }

    private func fetch(generation: Int) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let queue = try await api.playbackQueue()
            guard generation == playbackGeneration else { return }
            entries = QueueEntry.entries(from: queue)
            readProblem = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == playbackGeneration else { return }
            readProblem = QueueProblem(error)
        }
    }
}
