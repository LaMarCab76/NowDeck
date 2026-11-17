import SwiftUI

/// One row of the Cola sheet: the same track data as the playlist detail, plus a small cover.
struct QueueEntry: Identifiable, Equatable, Sendable {
    var track: CollectionTrack
    var artworkURL: URL?

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
                artworkURL: Self.thumbnail(track.album?.images ?? [])
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
        }
    }
}

/// State of the Cola sheet.
///
/// The queue is read when the sheet opens, when the player shows another track while the
/// sheet is open (`trackDidChange()`) and on pull to refresh. It is **not** polled: the
/// player's polling already spends the request quota (docs/03, "Polling y estado local").
@MainActor
final class QueueModel: ObservableObject {
    /// `nil` until the first answer arrives.
    @Published private(set) var entries: [QueueEntry]?
    /// The last problem, shown until the next successful read. A list already on screen
    /// stays below it.
    @Published private(set) var problem: QueueProblem?
    @Published private(set) var isLoading = false

    private let api: SpotifyAPI
    /// The only worker that reads the queue. Reads never overlap, so an older answer can
    /// never land after a newer one.
    private var loadTask: Task<Void, Never>?
    /// Set when the track changed while the worker was reading: that read may carry the old
    /// queue, so the worker reads once more before finishing.
    private var needsAnotherRead = false

    init(api: SpotifyAPI) {
        self.api = api
    }

    /// Reads the queue. A reload while a read is running waits for it instead of sending a
    /// second request.
    func reload() async {
        await worker().value
    }

    /// The player moved to another track: the queue moved with it. A read already running
    /// may carry the old queue, so the worker reads again after it. Several changes during
    /// one read ask for a single extra read.
    func trackDidChange() async {
        if loadTask != nil { needsAnotherRead = true }
        await worker().value
    }

    /// The running worker, or a new one. Everything here runs on the main actor, and there
    /// is no suspension between the last check of `needsAnotherRead` and clearing
    /// `loadTask`, so a request for another read is never lost.
    private func worker() -> Task<Void, Never> {
        if let loadTask { return loadTask }
        let task = Task {
            repeat {
                needsAnotherRead = false
                await fetch()
            } while needsAnotherRead
            loadTask = nil
        }
        loadTask = task
        return task
    }

    private func fetch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let queue = try await api.playbackQueue()
            entries = QueueEntry.entries(from: queue)
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            problem = QueueProblem(error)
        }
    }
}
