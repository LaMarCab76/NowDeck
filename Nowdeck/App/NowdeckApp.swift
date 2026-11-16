import SwiftUI

@main
struct NowdeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var appState = AppState()
    @StateObject private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(themeStore)
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
