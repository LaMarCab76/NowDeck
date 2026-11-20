import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        Group {
            switch appState.route {
            case .onboarding(let step):
                OnboardingView(step: step)
            case .player:
                player
                    .statusBarHidden(true)
                    // The phone sits on a desk: hide the home indicator.
                    .persistentSystemOverlays(.hidden)
                    // After the setup, the player fades in while the screen rotates.
                    .transition(.opacity)
            }
        }
        // Portrait during the setup, landscape everywhere else (`OrientationController`).
        .orientationLock(following: appState.route)
    }

    @ViewBuilder
    private var player: some View {
        if let tokenManager = appState.tokenManager {
            PlayerScreen(model: PlayerModel(api: SpotifyAPI(tokens: tokenManager)),
                         playlistAccess: appState.playlistEditingAccess)
                // A new login gets a new token manager, and with it a fresh player state.
                .id(ObjectIdentifier(tokenManager))
        } else {
            // Not reachable: the player route always comes with a token manager.
            themeStore.palette.background.color
                .ignoresSafeArea()
        }
    }
}
