import SwiftUI

/// Biblioteca (`Biblioteca.dc.html`): tabs Biblioteca / Buscar, filters, a row of cards and
/// the mini player.
///
/// The player presents it full screen. Tapping a card plays it on the active device and
/// goes back to the player; tapping the mini player goes back too.
///
/// Two actions belong to other milestones and come in as closures:
/// - `onShowDevices`: the devices sheet (milestone 4). Called by "Suena en …" and when
///   playing a card fails because there is no active device.
/// - `onPlayPause`: play/pause (milestone 3).
struct LibraryScreen: View {
    @StateObject private var model: LibraryModel
    @ObservedObject var player: PlayerModel
    var onPlayPause: () -> Void
    var onShowDevices: () -> Void

    @State private var tab: LibraryContent.Tab = .library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var theme: ThemeStore

    init(model: @autoclosure @escaping () -> LibraryModel, player: PlayerModel,
         onPlayPause: @escaping () -> Void, onShowDevices: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model())
        self.player = player
        self.onPlayPause = onPlayPause
        self.onShowDevices = onShowDevices
    }

    var body: some View {
        LibraryContent(model: model, player: player, controls: player.controls, tab: $tab,
                       onPlay: play, onOpenPlayer: { dismiss() },
                       onPlayPause: onPlayPause, onShowDevices: onShowDevices)
            .orientationLock(.landscape)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .task { await model.open() }
            // The mini player needs fresh data. `start()` does nothing if the player is
            // already polling, so this is safe whatever the presenting screen does.
            .onAppear { if scenePhase == .active { player.start() } }
            .onChange(of: scenePhase) { phase in
                if phase == .active { player.start() } else { player.stop() }
            }
    }

    private func play(_ item: LibraryEntry) {
        Task {
            switch await model.play(item) {
            case .started:
                // Confirm the new state soon (docs/03, "Después de un comando") and go back
                // to the player, as the design asks.
                player.refresh(after: 0.6)
                dismiss()
            case .openInSpotify(let url):
                SpotifyLink.open(url)
            case .noActiveDevice:
                onShowDevices()
            case .failed, .ignored:
                break
            }
        }
    }
}

/// The library for a given model state. Separate from `LibraryScreen` so previews and the
/// screenshot checks can render it without loading anything.
struct LibraryContent: View {
    enum Tab: Equatable {
        case library
        case search
    }

    @ObservedObject var model: LibraryModel
    @ObservedObject var player: PlayerModel
    /// The player's commands: the mini player's play button can fail while the library
    /// covers the player, so their notices show here.
    @ObservedObject var controls: PlayerControlsModel
    @Binding var tab: Tab
    var onPlay: (LibraryEntry) -> Void
    var onOpenPlayer: () -> Void
    var onPlayPause: () -> Void
    var onShowDevices: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        // Same approach as `ScreenMargins`: the reader respects the safe area so it can
        // report the insets, and the content is laid out on the full screen with the larger
        // of the mockup margin and the safe area on each side.
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let fullWidth = proxy.size.width + insets.leading + insets.trailing
            let fullHeight = proxy.size.height + insets.top + insets.bottom
            let leading = max(Layout.horizontal, insets.leading)
            let trailing = max(Layout.horizontal, insets.trailing)

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 0)
                switch tab {
                case .library:
                    LibraryFilterBar(filters: model.filters, selected: model.filter) { filter in
                        Task { await model.select(filter) }
                    }
                    Spacer(minLength: 0)
                    LibraryRow(state: model.state(of: model.filter),
                               startingURI: model.startingURI,
                               trailingMargin: trailing,
                               onPlay: onPlay,
                               onRetry: { Task { await model.retry() } })
                        // The row slides under the right margin up to the screen edge.
                        .padding(.trailing, -trailing)
                case .search:
                    LibrarySearchView()
                }
                Spacer(minLength: 0)
                MiniPlayerView(item: player.nowPlaying,
                               artwork: player.artwork,
                               artworkColor: player.artworkColor,
                               device: player.playback?.device,
                               isPlaying: player.playback?.isPlaying == true,
                               onOpenPlayer: onOpenPlayer,
                               onShowDevices: onShowDevices,
                               onPlayPause: onPlayPause)
            }
            .padding(.top, max(Layout.top, insets.top))
            // The home indicator is hidden here too: the mockup's 10 pt are enough.
            .padding(.bottom, Layout.bottom)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .frame(width: fullWidth, height: fullHeight, alignment: .topLeading)
            .offset(x: -insets.leading, y: -insets.top)
        }
        .foregroundStyle(theme.palette.text.color)
        .background(theme.palette.background.color.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let notice = model.notice {
                LibraryNoticeView(notice: notice)
                    .padding(.top, Metrics.Notice.top)
                    .transition(.opacity)
            } else if let notice = controls.notice {
                ControlNoticeView(notice: notice)
                    .padding(.top, Metrics.Notice.top)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .animation(.easeInOut(duration: 0.2), value: controls.notice)
    }

    private var header: some View {
        HStack(spacing: Layout.rowGap) {
            LibraryTabs(tab: $tab)
            Spacer(minLength: 0)
            SpotifyLogoLink(url: SpotifyLink.home)
        }
        .frame(height: Layout.rowHeight)
    }
}

// MARK: - Tabs

/// The segmented control Biblioteca / Buscar.
struct LibraryTabs: View {
    @Binding var tab: LibraryContent.Tab

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        HStack(spacing: Layout.tabTrackPadding) {
            tabButton(.library, leadingPadding: Layout.tabHorizontalPadding) {
                Text("Biblioteca")
            }
            tabButton(.search, leadingPadding: Layout.searchTabLeadingPadding) {
                HStack(spacing: Layout.tabIconGap) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: Layout.tabIconSize - 2, weight: .bold))
                        .accessibilityHidden(true)
                    Text("Buscar")
                }
            }
        }
        .padding(Layout.tabTrackPadding)
        .frame(height: Layout.rowHeight)
        .background(Capsule().fill(Palette.libraryTabTrack))
        // Moved left so the active tab lines up with the filters below.
        .padding(.leading, Layout.tabTrackOffset)
    }

    private func tabButton<Label: View>(_ value: LibraryContent.Tab, leadingPadding: CGFloat,
                                        @ViewBuilder label: () -> Label) -> some View {
        let isSelected = tab == value
        return Button { tab = value } label: {
            label()
                .textStyle(.libraryTab)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Palette.playButtonIcon : theme.palette.text.color)
                .padding(.leading, leadingPadding)
                .padding(.trailing, Layout.tabHorizontalPadding)
                .frame(height: Layout.tabHeight)
                .background(Capsule().fill(isSelected ? theme.palette.text.color : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The 36 pt tab sits in the 44 pt track, which pads the tap area.
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Notice

/// The light pill at the top, like the lyrics notice (`LyricsNoticeView`), for 3 s.
struct LibraryNoticeView: View {
    let notice: LibraryModel.Notice
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: Metrics.Notice.iconSpacing) {
            Image(systemName: notice == .noActiveDevice ? "hifispeaker" : "exclamationmark.circle")
                .font(.system(size: Metrics.Notice.iconSize - 3, weight: .semibold))
                .frame(width: Metrics.Notice.iconSize, height: Metrics.Notice.iconSize)
                .accessibilityHidden(true)
            Text(message)
                .textStyle(.notice)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Palette.noticeForeground)
        .padding(.leading, Metrics.Notice.leadingPadding)
        .padding(.trailing, Metrics.Notice.trailingPadding)
        .frame(height: Metrics.Notice.height)
        .background(Capsule().fill(theme.palette.text.color))
        .shadow(color: Palette.noticeShadow, radius: Metrics.Notice.shadowRadius,
                y: Metrics.Notice.shadowY)
        .accessibilityElement(children: .combine)
        // Announced like the player's notices, again if it changes while on screen.
        .onAppear { AccessibilityAnnouncement.post(message) }
        .onChange(of: notice) { _ in AccessibilityAnnouncement.post(message) }
    }

    private var message: LocalizedStringResource {
        switch notice {
        case .noActiveDevice: return "No hay un dispositivo activo. Elegí uno para escuchar."
        case .forbidden: return "Spotify no dejó reproducirlo. Revisá que tu cuenta tenga Premium."
        case .rateLimited: return "Spotify pidió esperar un momento. Probá de nuevo en un rato."
        case .playbackFailed: return "No pudimos reproducirlo. Probá de nuevo."
        }
    }
}
