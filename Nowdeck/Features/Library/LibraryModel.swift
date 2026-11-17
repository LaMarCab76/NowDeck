import Foundation

/// State of the library screen: one row of cards per filter, loaded when the filter is
/// first shown, and the "play this card" command.
///
/// - Rows hold at most `rowLimit` (20) cards, as Spotify's guidelines ask. When a page
///   drops unusable items (no URI, `null`), the next page is fetched, up to `maxPages`.
/// - The Audiobooks filter appears only once `GET /me/audiobooks` answers with at least
///   one audiobook. Audiobooks exist only in a few markets and `GET /me` no longer says the
///   user's country (removed in February 2026), so "has saved audiobooks" is the only
///   honest signal. A failed or empty answer keeps the filter hidden.
@MainActor
final class LibraryModel: ObservableObject {
    enum RowState: Equatable {
        case idle
        case loading
        case loaded([LibraryEntry])
        case failed(LoadFailure)
    }

    enum LoadFailure: Equatable {
        /// `403`: the account cannot use this app (or the library), see
        /// `SpotifyAPIError.forbidden`.
        case forbidden
        /// `429`: Spotify asked to wait.
        case rateLimited
        /// Network or server error.
        case failed
    }

    /// What tapping a card did. The view acts on it (refresh the player, open the devices
    /// sheet, open Spotify).
    enum PlayOutcome: Equatable {
        case started
        /// Podcasts and audiobooks: open the item in Spotify.
        case openInSpotify(URL?)
        /// `404`: there is no active device to play on.
        case noActiveDevice
        case failed
        /// Another card is still starting.
        case ignored
    }

    /// Short messages shown as a pill at the top of the screen.
    enum Notice: Equatable {
        case noActiveDevice
        case forbidden
        case rateLimited
        case playbackFailed
    }

    static let rowLimit = SpotifyAPI.libraryPageSize
    static let maxPages = 3

    @Published private(set) var filter: LibraryFilter = .playlists
    @Published private(set) var rows: [LibraryFilter: RowState] = [:]
    @Published private(set) var showsAudiobooks = false
    /// URI of the card whose playback is starting.
    @Published private(set) var startingURI: String?
    @Published private(set) var notice: Notice?

    private let api: SpotifyAPI
    private var noticeTask: Task<Void, Never>?

    init(api: SpotifyAPI) {
        self.api = api
    }

    /// The filters to show, in the mockup's order.
    var filters: [LibraryFilter] {
        LibraryFilter.allCases.filter { $0 != .audiobooks || showsAudiobooks }
    }

    func state(of filter: LibraryFilter) -> RowState {
        rows[filter] ?? .idle
    }

    // MARK: Loading

    /// Loads the selected row and checks whether there are audiobooks. Called when the
    /// screen appears.
    func open() async {
        async let selected: Void = load(filter)
        async let audiobooks: Void = load(.audiobooks)
        _ = await (selected, audiobooks)
    }

    func select(_ newFilter: LibraryFilter) async {
        filter = newFilter
        switch state(of: newFilter) {
        case .idle, .failed: await load(newFilter)
        case .loading, .loaded: break
        }
    }

    func retry() async {
        await load(filter)
    }

    func load(_ filter: LibraryFilter) async {
        if case .loading = state(of: filter) { return }
        rows[filter] = .loading
        do {
            let items = try await Self.collectRow(fetch: fetcher(for: filter))
            rows[filter] = .loaded(items)
            if filter == .audiobooks { showsAudiobooks = !items.isEmpty }
        } catch is CancellationError {
            rows[filter] = .idle
        } catch {
            rows[filter] = .failed(Self.failure(for: error))
            if filter == .audiobooks { showsAudiobooks = false }
        }
    }

    /// One page of a row: its usable items and where the next page starts.
    typealias PageFetch = @Sendable (_ offset: Int) async throws
        -> (items: [LibraryEntry], nextOffset: Int?)

    /// Fetches pages until the row has `rowLimit` items, there are no more pages, or
    /// `maxPages` pages were read. Duplicate URIs are dropped.
    static func collectRow(limit: Int = rowLimit, maxPages: Int = maxPages,
                           fetch: PageFetch) async throws -> [LibraryEntry] {
        var items: [LibraryEntry] = []
        var seen = Set<String>()
        var offset: Int? = 0
        var pages = 0
        while let current = offset, items.count < limit, pages < maxPages {
            let page = try await fetch(current)
            pages += 1
            for item in page.items where seen.insert(item.uri).inserted {
                items.append(item)
            }
            offset = page.nextOffset
        }
        return Array(items.prefix(limit))
    }

    private func fetcher(for filter: LibraryFilter) -> PageFetch {
        let api = self.api
        switch filter {
        case .playlists:
            return { offset in
                let page = try await api.savedPlaylists(offset: offset)
                return (page.items.compactMap(LibraryEntry.init(playlist:)), page.nextOffset)
            }
        case .albums:
            return { offset in
                let page = try await api.savedAlbums(offset: offset)
                return (page.items.compactMap { LibraryEntry(album: $0.album) }, page.nextOffset)
            }
        case .shows:
            return { offset in
                let page = try await api.savedShows(offset: offset)
                return (page.items.compactMap { LibraryEntry(show: $0.show) }, page.nextOffset)
            }
        case .audiobooks:
            return { offset in
                let page = try await api.savedAudiobooks(offset: offset)
                return (page.items.compactMap(LibraryEntry.init(audiobook:)), page.nextOffset)
            }
        }
    }

    private static func failure(for error: Error) -> LoadFailure {
        switch error {
        case SpotifyAPIError.forbidden: return .forbidden
        case SpotifyAPIError.rateLimited: return .rateLimited
        default: return .failed
        }
    }

    // MARK: Playing a card

    /// Starts the card on the active device (albums and playlists), or says to open it in
    /// Spotify (podcasts and audiobooks, see `LibraryEntry.playsInPlace`).
    func play(_ item: LibraryEntry) async -> PlayOutcome {
        guard item.playsInPlace else { return .openInSpotify(item.pageURL) }
        guard startingURI == nil else { return .ignored }

        startingURI = item.uri
        defer { startingURI = nil }
        do {
            try await api.playContext(uri: item.uri)
            return .started
        } catch SpotifyAPIError.notFound {
            show(.noActiveDevice)
            return .noActiveDevice
        } catch SpotifyAPIError.forbidden {
            show(.forbidden)
            return .failed
        } catch SpotifyAPIError.rateLimited {
            show(.rateLimited)
            return .failed
        } catch is CancellationError {
            return .ignored
        } catch {
            show(.playbackFailed)
            return .failed
        }
    }

    // MARK: Notice

    /// Shows a notice for `Metrics.Notice.duration` (3 s), like the lyrics notice.
    func show(_ newNotice: Notice) {
        noticeTask?.cancel()
        notice = newNotice
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Metrics.Notice.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
