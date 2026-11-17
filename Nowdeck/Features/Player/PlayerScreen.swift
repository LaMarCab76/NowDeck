import SwiftUI

/// What the player's buttons do. Milestone 2 only reads: every action is a no-op until
/// milestones 3 (controls), 4 (devices) and 5 (library) wire them. Links back to Spotify are
/// already active (`SpotifyLink`).
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
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.scenePhase) private var scenePhase

    var actions = PlayerActions()
    /// "Mostrar letras" (Ajustes → Reproductor, milestone 7). Off by default (docs/06).
    var showsLyricsButton = false

    init(model: @autoclosure @escaping () -> PlayerModel, actions: PlayerActions = PlayerActions(),
         showsLyricsButton: Bool = false) {
        _model = StateObject(wrappedValue: model())
        self.actions = actions
        self.showsLyricsButton = showsLyricsButton
    }

    var body: some View {
        PlayerContent(model: model, actions: actions, showsLyricsButton: showsLyricsButton)
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
                    PlayerView(model: model, actions: actions, showsLyricsButton: showsLyricsButton,
                               screenWidth: width)
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
        guard model.status == .active, let dominant = model.artworkColor else {
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
