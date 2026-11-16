import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        switch appState.route {
        case .player:
            // Placeholder until milestone 2: an empty landscape screen on the theme background.
            themeStore.palette.background.color
                .ignoresSafeArea()
                .orientationLock(.landscape)
                .statusBarHidden(true)
                // The phone sits on a desk: hide the home indicator.
                .persistentSystemOverlays(.hidden)
        }
    }
}
