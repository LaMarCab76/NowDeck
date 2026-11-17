import Foundation

/// The state of lyrics mode for the player screen.
///
/// The player (milestone 2) owns one as a `@StateObject` and:
/// - calls `toggle(for:)` when the lyrics button is tapped;
/// - calls `trackDidChange(to:)` whenever the playing item changes;
/// - calls `turnOff()` when "Mostrar letras" is switched off in Settings;
/// - shows `LyricsModeView` while `showsLyricsMode` is true, and `LyricsNoticeView` while
///   `notice` is not `nil`.
///
/// Flow (docs/01-producto.md, "Letras"): tapping the button looks the lyrics up and keeps the
/// normal view until they arrive. If there are none, the notice appears for 3 s and the player
/// stays in (or goes back to) the normal view.
@MainActor
final class LyricsModeController: ObservableObject {
    enum State: Equatable {
        case off
        /// Looking up lyrics for `track`. `showsMode` keeps lyrics mode on screen (empty) when
        /// the track changed while it was open.
        case loading(LyricsTrack, showsMode: Bool)
        case showing(LyricsTrack, SyncedLyrics)
    }

    enum Notice: Equatable {
        /// "No encontramos la letra de este tema".
        case notFound
        /// The lookup failed (no connection, LRCLIB busy).
        case failed
    }

    @Published private(set) var state: State = .off
    @Published private(set) var notice: Notice?

    private let provider: LyricsProviding
    private let noticeDuration: TimeInterval
    private var loadTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(provider: LyricsProviding = LyricsService(),
         noticeDuration: TimeInterval = Metrics.Notice.duration) {
        self.provider = provider
        self.noticeDuration = noticeDuration
    }

    /// The lyrics button is drawn as active (accent on accent 16 %).
    var isButtonActive: Bool { state != .off }

    /// Lyrics mode replaces the top block of the player.
    var showsLyricsMode: Bool {
        switch state {
        case .off: return false
        case .loading(_, let showsMode): return showsMode
        case .showing: return true
        }
    }

    /// The lyrics on screen; `nil` while the ones of a new track load.
    var lyrics: SyncedLyrics? {
        if case .showing(_, let lyrics) = state { return lyrics }
        return nil
    }

    func toggle(for track: LyricsTrack?) {
        guard state == .off else {
            turnOff()
            return
        }
        guard let track else { return }
        load(track, showsMode: false)
    }

    func trackDidChange(to track: LyricsTrack?) {
        let current: LyricsTrack
        let showsMode: Bool
        switch state {
        case .off: return
        case .loading(let loading, let shows): current = loading; showsMode = shows
        case .showing(let showing, _): current = showing; showsMode = true
        }
        guard track != current else { return }
        guard let track else {
            turnOff()
            return
        }
        load(track, showsMode: showsMode)
    }

    func turnOff() {
        loadTask?.cancel()
        loadTask = nil
        state = .off
    }

    private func load(_ track: LyricsTrack, showsMode: Bool) {
        loadTask?.cancel()
        state = .loading(track, showsMode: showsMode)
        loadTask = Task { [provider] in
            let result = await provider.lyrics(for: track)
            // A newer tap or track change replaced this lookup.
            guard !Task.isCancelled, case .loading(track, _) = self.state else { return }
            switch result {
            case .found(let lyrics):
                self.state = .showing(track, lyrics)
            case .notFound:
                self.state = .off
                self.show(.notFound)
            case .failed:
                self.state = .off
                self.show(.failed)
            }
        }
    }

    private func show(_ notice: Notice) {
        noticeTask?.cancel()
        self.notice = notice
        let duration = noticeDuration
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.notice = nil
        }
    }
}
