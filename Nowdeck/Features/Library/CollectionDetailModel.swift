import Foundation

/// One row of the detail screen's track list.
struct CollectionTrack: Identifiable, Equatable, Sendable {
    /// Position in the list. Not the URI: a playlist can hold the same track twice.
    var id: Int
    /// Shown number, starting at 1.
    var number: Int
    var title: String
    /// Artists of a track, or the podcast of an episode. Verbatim from Spotify.
    var subtitle: String
    var durationMs: Int?
    var isExplicit: Bool
    /// `false` for local files and for tracks Spotify marks as not playable or restricted.
    /// They are dimmed.
    var isAvailable: Bool
    /// The track's page on `open.spotify.com`; `nil` for local files.
    var pageURL: URL?
}

extension CollectionTrack {
    /// `nil` when the item has no name: there would be nothing to show.
    init?(item: CollectionItem, isLocal: Bool = false, position: Int) {
        guard let name = item.name, !name.isEmpty else { return nil }
        let names: [String]
        if item.type == "episode" {
            names = [item.show?.name].compactMap { $0 }
        } else {
            names = (item.artists ?? []).compactMap(\.name)
        }
        let local = isLocal || item.isLocal == true
        self.init(
            id: position,
            number: position + 1,
            title: name,
            subtitle: names.filter { !$0.isEmpty }.joined(separator: ", "),
            durationMs: item.durationMs,
            isExplicit: item.explicit == true,
            isAvailable: !local && item.isPlayable != false && item.restrictions == nil,
            pageURL: local ? nil : NowPlaying.pageURL(externalURL: item.externalUrls?.spotify,
                                                      uri: item.uri)
        )
    }
}

/// State of the detail screen of a playlist or an album: its track list, loaded in pages of
/// 50 as the list scrolls.
///
/// Playback is not here: the "Reproducir" button plays the whole playlist or album through
/// `LibraryModel.play(_:)`, like a card did before, so the notices and the "starting" state
/// stay in one place.
@MainActor
final class CollectionDetailModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        /// `403` on a playlist's items: Spotify lists the tracks only of playlists the user
        /// owns or collaborates on. The screen says so and still offers to play it.
        case restricted
        case failed(LibraryModel.LoadFailure)
    }

    /// One page of the list: its usable rows, the total count Spotify reports and where the
    /// next page starts. `firstPosition` is the number of rows already shown.
    typealias PageFetch = @Sendable (_ offset: Int, _ firstPosition: Int) async throws
        -> (tracks: [CollectionTrack], total: Int?, nextOffset: Int?)

    let entry: LibraryEntry

    @Published private(set) var state: State = .loading
    @Published private(set) var tracks: [CollectionTrack] = []
    /// What Spotify reports as the total, which also counts items the list drops (`null`
    /// entries).
    @Published private(set) var total: Int?
    @Published private(set) var isLoadingMore = false
    /// The last "load more" failed; the list ends with "Reintentar".
    @Published private(set) var loadMoreFailed = false

    private let fetch: PageFetch
    private var nextOffset: Int?
    private var isLoadingFirstPage = false

    init(entry: LibraryEntry, fetch: @escaping PageFetch) {
        self.entry = entry
        self.fetch = fetch
    }

    convenience init(entry: LibraryEntry, api: SpotifyAPI) {
        self.init(entry: entry, fetch: Self.fetcher(for: entry, api: api))
    }

    /// Whether there are pages left to load.
    var hasMore: Bool { nextOffset != nil }

    /// Number of tracks for the list's label.
    var trackCount: Int { total ?? tracks.count }

    /// The sum of the durations, once every page is loaded. With pages left it would be a
    /// partial sum, so it is not shown.
    var totalDurationMs: Int? {
        guard state == .loaded, !hasMore, !tracks.isEmpty else { return nil }
        return tracks.reduce(0) { $0 + ($1.durationMs ?? 0) }
    }

    /// "48 TEMAS · 2 H 51 MIN", or only the count while pages are left.
    var listLabel: String {
        let count = trackCount
        let tracksText = count == 1
            ? String(localized: "1 TEMA", comment: "Detail track list label: one track")
            : String(localized: "\(count) TEMAS", comment: "Detail track list label: number of tracks")
        guard let duration = totalDurationMs, duration > 0 else { return tracksText }
        return tracksText + " · " + Self.durationLabel(ms: duration)
    }

    /// "41 MIN", "2 H 51 MIN" or "3 H", rounded to the nearest minute (at least 1).
    nonisolated static func durationLabel(ms: Int) -> String {
        let minutes = max(1, (ms + 30_000) / 60_000)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 {
            return String(localized: "\(rest) MIN", comment: "Total duration under an hour")
        }
        if rest == 0 {
            return String(localized: "\(hours) H", comment: "Total duration in whole hours")
        }
        return String(localized: "\(hours) H \(rest) MIN", comment: "Total duration: hours and minutes")
    }

    // MARK: Loading

    /// Loads the first page unless it is already loaded (or Spotify already said no). A load
    /// cut short by the screen going away leaves `.loading`, so it runs again.
    func loadIfNeeded() async {
        guard state == .loading else { return }
        await load()
    }

    /// Loads the first page. Called when the screen appears and by "Reintentar".
    func load() async {
        guard !isLoadingFirstPage, !isLoadingMore else { return }
        isLoadingFirstPage = true
        defer { isLoadingFirstPage = false }

        state = .loading
        tracks = []
        total = nil
        nextOffset = nil
        loadMoreFailed = false
        do {
            try await loadNextVisiblePage(from: 0)
            state = .loaded
        } catch is CancellationError {
            // The screen went away; it loads again if it comes back.
        } catch SpotifyAPIError.forbidden where entry.kind == .playlist {
            state = .restricted
        } catch {
            state = .failed(Self.failure(for: error))
        }
    }

    /// Loads the next page, when the end of the list comes into view.
    func loadMore() async {
        guard state == .loaded, let offset = nextOffset, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            try await loadNextVisiblePage(from: offset)
        } catch is CancellationError {
            // Nothing: the next appearance of the end of the list tries again.
        } catch {
            loadMoreFailed = true
        }
    }

    /// A page may contain only items that cannot be shown. Follow the next offset until
    /// there are rows or the collection ends. If a request fails, retry from that offset.
    private func loadNextVisiblePage(from firstOffset: Int) async throws {
        var offset = firstOffset
        while true {
            try Task.checkCancellation()
            let page = try await fetch(offset, tracks.count)
            try Task.checkCancellation()
            if let pageTotal = page.total { total = pageTotal }
            // A next offset that does not move forward would loop forever.
            nextOffset = page.nextOffset.flatMap { $0 > offset ? $0 : nil }
            tracks += page.tracks
            guard page.tracks.isEmpty, let nextOffset else { return }
            offset = nextOffset
        }
    }

    private static func failure(for error: Error) -> LibraryModel.LoadFailure {
        switch error {
        case SpotifyAPIError.forbidden: return .forbidden
        case SpotifyAPIError.rateLimited: return .rateLimited
        default: return .failed
        }
    }

    // MARK: Fetching

    private static func fetcher(for entry: LibraryEntry, api: SpotifyAPI) -> PageFetch {
        let id = SpotifyURI(entry.uri)?.id ?? ""
        switch entry.kind {
        case .album:
            return { offset, firstPosition in
                let page = try await api.albumTracks(albumID: id, offset: offset)
                return (Self.rows(page.items.map { ($0, false) }, from: firstPosition),
                        page.total, page.nextOffset)
            }
        case .playlist:
            return { offset, firstPosition in
                let page = try await api.playlistItems(playlistID: id, offset: offset)
                let items = page.items.compactMap { playlistItem in
                    playlistItem.content.map { ($0, playlistItem.isLocal == true) }
                }
                return (Self.rows(items, from: firstPosition), page.total, page.nextOffset)
            }
        case .show, .audiobook:
            // Podcasts and audiobooks open in Spotify and never get a detail screen.
            return { _, _ in ([], 0, nil) }
        }
    }

    /// Numbers the rows of a page after the ones already shown, dropping items without a
    /// name.
    nonisolated static func rows(_ items: [(CollectionItem, Bool)],
                                 from firstPosition: Int) -> [CollectionTrack] {
        var rows: [CollectionTrack] = []
        for (item, isLocal) in items {
            if let row = CollectionTrack(item: item, isLocal: isLocal,
                                         position: firstPosition + rows.count) {
                rows.append(row)
            }
        }
        return rows
    }
}
