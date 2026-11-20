import SwiftUI

/// What the player's buttons do. `PlayerScreen` wires them all. Ajustes is not here: it
/// opens from the library (owner's request, 2026-11-17). Links back to Spotify go through
/// `SpotifyLink`.
struct PlayerActions {
    var playPause: () -> Void = {}
    var previous: () -> Void = {}
    var next: () -> Void = {}
    /// −15 s and +15 s, shown instead of previous and next for podcast episodes.
    var skipBackward: () -> Void = {}
    var skipForward: () -> Void = {}
    /// Moves the playback to a position in ms (progress bar, lyrics mode).
    var seek: (Int) -> Void = { _ in }
    var shuffle: () -> Void = {}
    var repeatMode: () -> Void = {}
    var volume: () -> Void = {}
    var lyrics: () -> Void = {}
    var library: () -> Void = {}
    /// "Reproduciendo en …" and "Elegir dispositivo".
    var devices: () -> Void = {}
    /// Cola: what comes next.
    var queue: () -> Void = {}
    /// Agregar a una playlist: the item that plays now.
    var addToPlaylist: () -> Void = {}
}

/// The landscape player: owns the polling model and picks between the player, "Nada
/// sonando" and the error states.
struct PlayerScreen: View {
    @StateObject private var model: PlayerModel
    @StateObject private var lyrics = LyricsModeController()
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.scenePhase) private var scenePhase
    /// The library and the two devices sheets (the player's and the library's).
    @StateObject private var presentation = PlayerPresentation()

    var actions = PlayerActions()
    /// Whether the session can edit playlists, and how to ask for it (`AppState`).
    var playlistAccess: PlaylistEditingAccess

    init(model: @autoclosure @escaping () -> PlayerModel, actions: PlayerActions = PlayerActions(),
         playlistAccess: PlaylistEditingAccess = .granted) {
        _model = StateObject(wrappedValue: model())
        self.actions = actions
        self.playlistAccess = playlistAccess
    }

    /// The caller's actions plus the ones the player owns: lyrics mode, the library and the
    /// playback controls.
    private var wiredActions: PlayerActions {
        var wired = actions
        wired.lyrics = { [lyrics, model] in lyrics.toggle(for: model.playback?.lyricsTrack) }
        // Milestone 3: playback controls and volume.
        let controls = model.controls
        wired.playPause = { controls.playPause() }
        wired.previous = { controls.previous() }
        wired.next = { controls.next() }
        wired.skipBackward = { controls.skipBackward() }
        wired.skipForward = { controls.skipForward() }
        wired.seek = { controls.seek(toMs: $0) }
        wired.shuffle = { controls.toggleShuffle() }
        wired.repeatMode = { controls.cycleRepeat() }
        wired.volume = { controls.volume.toggleButton() }
        // Milestone 4: devices sheet.
        wired.devices = { [presentation] in presentation.showDevices() }
        // Milestone 5: library.
        wired.library = { [presentation] in presentation.showsLibrary = true }
        // Playback queue: tapping a track asks to play it.
        wired.queue = { [presentation] in presentation.showsQueue = true }
        // Agregar a una playlist (2026-11-18).
        wired.addToPlaylist = { [presentation] in presentation.showAddToPlaylist() }
        return wired
    }

    var body: some View {
        PlayerContent(model: model, lyrics: lyrics, controls: model.controls,
                      actions: wiredActions, showsLyricsButton: theme.showsLyricsButton,
                      // With the library open, it shows the control notices itself.
                      showsNotices: presentation.visibleSurface == .player)
            // A command answered "no active device": offer the device list (milestone 4) on
            // the screen the user is looking at, the player or the library.
            .onReceive(model.controls.noActiveDevice) { presentation.showDevices() }
            .onChange(of: model.playback?.lyricsTrack) { track in
                lyrics.trackDidChange(to: track)
            }
            // "Mostrar letras" turned off in Settings: leave lyrics mode.
            .onChange(of: theme.showsLyricsButton) { isOn in
                if !isOn { lyrics.turnOff() }
            }
            .devicesSheet(isPresented: $presentation.showsDevices, player: model)
            .queueSheet(isPresented: $presentation.showsQueue, player: model)
            .addToPlaylistSheet(isPresented: $presentation.showsAddToPlaylist, player: model,
                                access: playlistAccess)
            .fullScreenCover(isPresented: $presentation.showsLibrary) {
                // While the library covers the player, the devices sheet ("Suena en …" in the
                // mini player, a card or a command that finds no active device) is presented
                // from inside the library.
                LibraryScreen(model: LibraryModel(
                                  api: model.api,
                                  // Experimental, only if the user turned it on.
                                  folders: preferences.usesPlaylistFolders
                                      ? PlaylistFolderClient(api: model.api) : nil),
                              player: model,
                              onPlayPause: wiredActions.playPause,
                              onShowDevices: { [presentation] in presentation.showDevices() },
                              onAddToPlaylist: wiredActions.addToPlaylist)
                    .devicesSheet(isPresented: $presentation.showsLibraryDevices, player: model)
                    .addToPlaylistSheet(isPresented: $presentation.showsLibraryAddToPlaylist,
                                        player: model, access: playlistAccess)
                    // Passed explicitly: a cover is a new view hierarchy, and Ajustes (opened
                    // from the library) needs it.
                    .environmentObject(preferences)
            }
            .onAppear {
                // Only "Foto del artista" asks Spotify for the photo.
                model.loadsArtistImages = theme.playerBackground == .artistPhoto
                if scenePhase == .active { model.start() }
            }
            .onChange(of: theme.playerBackground) {
                model.loadsArtistImages = $0 == .artistPhoto
            }
            // Covered by the library or Cola, the player is "gone" but its data is still
            // on screen (`keepsPlayerPolling`).
            .onDisappear { if !presentation.keepsPlayerPolling { model.stop() } }
            // iOS 16 API (the two-value variant is iOS 17+).
            .onChange(of: scenePhase) { phase in
                if phase == .active { model.start() } else { model.stop() }
            }
    }
}

/// The screen for a given model state. Separate from `PlayerScreen` so previews and the
/// screenshot checks can render it without polling.
struct PlayerContent: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var lyrics: LyricsModeController
    @ObservedObject var controls: PlayerControlsModel
    @EnvironmentObject private var theme: ThemeStore
    var actions: PlayerActions
    var showsLyricsButton: Bool
    /// `false` while another screen (the library) covers the player and shows the notices.
    var showsNotices = true

    @State private var swipe: TrackSwipePhase = .idle
    /// Where a swipe may start (the cover and title band), from `PlayerView`.
    @State private var swipeBand: ClosedRange<CGFloat>?

    var body: some View {
        ZStack {
            PlayerBackgroundView(color: backgroundColor,
                                 artistImage: model.status == .active ? model.artistImage : nil,
                                 blur: theme.backgroundBlur, dim: theme.backgroundDim)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: backgroundColor)

            switch model.status {
            case .loading:
                Color.clear
            case .active:
                ScreenMargins(top: Spacing.Player.top, bottom: Spacing.Player.bottom) { width in
                    PlayerView(model: model, lyrics: lyrics, actions: actions,
                               showsLyricsButton: showsLyricsButton, screenWidth: width,
                               swipe: swipe)
                }
                .overlay(alignment: .top) {
                    // A failed command is newer news than the lyrics notice: show it instead.
                    if !showsNotices {
                        EmptyView()
                    } else if let notice = controls.notice {
                        ControlNoticeView(notice: notice)
                            .padding(.top, Metrics.Notice.top)
                            .transition(.opacity)
                    } else if let notice = lyrics.notice {
                        LyricsNoticeView(notice: notice)
                            .padding(.top, Metrics.Notice.top)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: controls.notice)
            case .nothingPlaying:
                emptyState(.nothingPlaying)
            case .accessDenied:
                emptyState(.accessDenied)
            case .unavailable:
                emptyState(.unavailable)
            }
        }
        // Next / previous by dragging left or right across the cover and title (in lyrics
        // mode, its bottom row): they follow the finger and the other item comes in from the
        // side.
        .trackSwipe(isActive: model.status == .active,
                    band: swipeBand, onChange: swipeChanged, onEnd: swipeEnded,
                    onCancel: settleDraggingSwipe)
        .onPreferenceChange(TrackSwipeBandKey.self) { swipeBand = $0 }
        .onChange(of: model.nowPlaying?.transitionKey) { key in
            // The item the swipe showed is now the current one: put the pages back without
            // animation (both show the same item, so nothing moves on screen).
            guard case let .landing(_, _, fromKey) = swipe, key != fromKey else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { swipe = .idle }
        }
        .task(id: swipe.isLanding) {
            // Spotify did not report another item (a failed command, or "previous" that only
            // restarted the track): slide back.
            guard swipe.isLanding else { return }
            try? await Task.sleep(nanoseconds: UInt64(Motion.swipeLandingTimeout * 1_000_000_000))
            guard !Task.isCancelled, swipe.isLanding else { return }
            withAnimation(Motion.swipeSettle) { swipe = .idle }
        }
    }

    private func swipeChanged(_ trackSwipe: TrackSwipe) {
        if swipe.isLanding { return }
        if swipe.edge != .right, trackSwipe.edge == .right { model.refreshUpNextIfStale() }
        swipe = .dragging(edge: trackSwipe.edge, distance: trackSwipe.distance,
                          isAllowed: isAllowed(trackSwipe.edge))
    }

    private func swipeEnded(_ trackSwipe: TrackSwipe, commits: Bool) {
        if swipe.isLanding { return }
        guard commits, isAllowed(trackSwipe.edge) else {
            settleDraggingSwipe()
            return
        }
        // The track changes under the finger: the phone confirms it (owner's request).
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let preview = trackSwipe.edge == .right ? model.upNext : model.previousTrack
        withAnimation(Motion.swipeLand) {
            swipe = .landing(edge: trackSwipe.edge, preview: preview,
                             fromKey: model.nowPlaying?.transitionKey)
        }
        switch trackSwipe.edge {
        case .left: actions.previous()
        case .right: actions.next()
        }
    }

    private func settleDraggingSwipe() {
        guard case .dragging = swipe else { return }
        withAnimation(Motion.swipeSettle) { swipe = .idle }
    }

    private func isAllowed(_ edge: TrackSwipe.Edge) -> Bool {
        let availability = ControlAvailability(playback: model.playback)
        return edge == .left ? availability.previous : availability.next
    }

    private func emptyState(_ kind: NothingPlayingView.Kind) -> some View {
        ScreenMargins(top: Metrics.EmptyState.topBottomPadding,
                      bottom: Metrics.EmptyState.topBottomPadding) { _ in
            NothingPlayingView(kind: kind, chooseDevice: actions.devices)
        }
    }

    /// The artwork color, softened for the theme's text; the theme background otherwise
    /// (empty states, no artwork, all-black covers).
    private var backgroundColor: Color {
        guard model.status == .active, theme.playerBackground.usesArtworkColor,
              let dominant = model.artworkColor else {
            return theme.palette.background.color
        }
        return ArtworkColor.playerBackground(from: dominant,
                                             readableWith: theme.palette.tertiaryText).color
    }
}

/// The design's margins measured from the screen edges, never less than the safe area.
///
/// The mockups use 48 pt side margins on the whole 896 pt width. On notched iPhones in
/// landscape the safe area is 44 pt on each side, so adding the margin *inside* the safe
/// area would leave 92 pt and squeeze the layout. Instead the margin is
/// `max(48, safe area)` from the physical edge: the design's 48 pt where it fits, and never
/// under the notch or the rounded corners.
struct ScreenMargins<Content: View>: View {
    var top: CGFloat
    var bottom: CGFloat
    var horizontal: CGFloat = Spacing.Player.horizontal
    @ViewBuilder var content: (_ screenWidth: CGFloat) -> Content

    var body: some View {
        // The reader respects the safe area so that it can report the insets (a reader that
        // ignores the safe area reports zero). The content is then sized to the full screen
        // and moved back to the physical top-left corner.
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let fullWidth = proxy.size.width + insets.leading + insets.trailing
            let fullHeight = proxy.size.height + insets.top + insets.bottom
            let side = max(horizontal, insets.leading, insets.trailing)
            content(fullWidth)
                .padding(.top, max(top, insets.top))
                // The home indicator is hidden on the player, so the bottom inset is not
                // respected: the design's 20 pt is enough to keep controls off the edge.
                .padding(.bottom, bottom)
                .padding(.horizontal, side)
                .frame(width: fullWidth, height: fullHeight)
                .offset(x: -insets.leading, y: -insets.top)
        }
    }
}
