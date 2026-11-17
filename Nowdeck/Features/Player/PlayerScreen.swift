import SwiftUI

/// What the player's buttons do. Lyrics and Settings are wired by `PlayerScreen`; the rest
/// are no-ops until milestones 3 (controls), 4 (devices) and 5 (library) wire them. Links
/// back to Spotify are already active (`SpotifyLink`).
struct PlayerActions {
    var playPause: () -> Void = {}
    var previous: () -> Void = {}
    var next: () -> Void = {}
    var shuffle: () -> Void = {}
    var repeatMode: () -> Void = {}
    var volume: () -> Void = {}
    var lyrics: () -> Void = {}
    var library: () -> Void = {}
    var settings: () -> Void = {}
    /// "Reproduciendo en …" and "Elegir dispositivo".
    var devices: () -> Void = {}
}

/// The landscape player: owns the polling model and picks between the player, "Nada
/// sonando" and the error states.
struct PlayerScreen: View {
    @StateObject private var model: PlayerModel
    @StateObject private var lyrics = LyricsModeController()
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSettings = false

    var actions = PlayerActions()

    init(model: @autoclosure @escaping () -> PlayerModel, actions: PlayerActions = PlayerActions()) {
        _model = StateObject(wrappedValue: model())
        self.actions = actions
    }

    /// The caller's actions plus the ones the player owns: lyrics mode and Settings.
    private var wiredActions: PlayerActions {
        var wired = actions
        wired.lyrics = { [lyrics, model] in lyrics.toggle(for: model.playback?.lyricsTrack) }
        wired.settings = { showsSettings = true }
        return wired
    }

    var body: some View {
        PlayerContent(model: model, lyrics: lyrics, actions: wiredActions,
                      showsLyricsButton: theme.showsLyricsButton)
            .onChange(of: model.playback?.lyricsTrack) { track in
                lyrics.trackDidChange(to: track)
            }
            // "Mostrar letras" turned off in Settings: leave lyrics mode.
            .onChange(of: theme.showsLyricsButton) { isOn in
                if !isOn { lyrics.turnOff() }
            }
            .fullScreenCover(isPresented: $showsSettings) {
                SettingsView()
            }
            .onAppear { if scenePhase == .active { model.start() } }
            .onDisappear { model.stop() }
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
    @EnvironmentObject private var theme: ThemeStore
    var actions: PlayerActions
    var showsLyricsButton: Bool

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: backgroundColor)

            switch model.status {
            case .loading:
                Color.clear
            case .active:
                ScreenMargins(top: Spacing.Player.top, bottom: Spacing.Player.bottom) { width in
                    PlayerView(model: model, lyrics: lyrics, actions: actions,
                               showsLyricsButton: showsLyricsButton, screenWidth: width)
                }
                .overlay(alignment: .top) {
                    if let notice = lyrics.notice {
                        LyricsNoticeView(notice: notice)
                            .padding(.top, Metrics.Notice.top)
                            .transition(.opacity)
                    }
                }
            case .nothingPlaying:
                emptyState(.nothingPlaying)
            case .accessDenied:
                emptyState(.accessDenied)
            case .unavailable:
                emptyState(.unavailable)
            }
        }
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
        guard model.status == .active, theme.playerBackground == .artwork,
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
