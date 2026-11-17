import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        switch appState.route {
        case .onboarding(let step):
            OnboardingView(step: step)
        case .player:
            player
                .orientationLock(.landscape)
                .statusBarHidden(true)
                // The phone sits on a desk: hide the home indicator.
                .persistentSystemOverlays(.hidden)
        }
    }

    @ViewBuilder
    private var player: some View {
        if let tokenManager = appState.tokenManager {
            PlayerScreen(model: PlayerModel(api: SpotifyAPI(tokens: tokenManager)))
                // A new login gets a new token manager, and with it a fresh player state.
                .id(ObjectIdentifier(tokenManager))
        } else {
            // Not reachable: the player route always comes with a token manager.
            themeStore.palette.background.color
                .ignoresSafeArea()
        }
    }
}
