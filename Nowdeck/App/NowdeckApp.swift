import SwiftUI

@main
struct NowdeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var appState = AppState()
    /// Saved in Application Support; see `ThemeStorage`.
    @StateObject private var themeStore = ThemeStore(storage: .applicationSupport())
    @StateObject private var themeImport = ThemeImportCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                // Theme files opened from Files or AirDrop. Only file URLs are handled: the
                // OAuth redirect (nowdeck://callback) never reaches here, it is captured by
                // ASWebAuthenticationSession.
                .onOpenURL { themeImport.handleOpenURL($0) }
                // The import sheet waits while onboarding (portrait) is on screen.
                .themeImportPresenter(isEnabled: appState.route == .player)
                .environmentObject(appState)
                .environmentObject(appState.preferences)
                .environmentObject(themeStore)
                .environmentObject(themeImport)
                .preferredColorScheme(.dark)
        }
        // Keep the screen on only while the app is in the foreground. iOS restores the
        // idle timer on its own when the app leaves, but setting it explicitly is clearer.
        // (`onChange(of:perform:)` is the iOS 16 API; the two-value variant is iOS 17+.)
        .onChange(of: scenePhase) { phase in
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
    }
}
