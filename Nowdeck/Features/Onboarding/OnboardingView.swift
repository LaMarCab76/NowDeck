import SwiftUI

/// The three first-launch screens, in portrait.
///
/// Steps are switched by `AppState` instead of a `NavigationStack`: the mockups have their
/// own "Atrás" button and no navigation bar, and `AppState` must be able to jump straight to
/// the Client ID step after an expired session.
struct OnboardingView: View {
    let step: AppState.OnboardingStep

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        ZStack {
            theme.palette.background.color
                .ignoresSafeArea()

            switch step {
            case .welcome:
                WelcomeView(onStart: { go(to: .createApp) })
                    .transition(.opacity)
            case .createApp:
                CreateAppView(onBack: { go(to: .welcome) },
                              onContinue: { go(to: .clientID) })
                    .transition(.opacity)
            case .clientID:
                ClientIDView(onBack: { go(to: .createApp) })
                    .transition(.opacity)
            }
        }
        .orientationLock(.portrait)
    }

    private func go(to step: AppState.OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.2)) {
            appState.dismissNotice()
            appState.showOnboardingStep(step)
        }
    }
}
