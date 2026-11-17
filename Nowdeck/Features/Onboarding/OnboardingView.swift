import SwiftUI

/// The first-launch screens, in portrait: the three of the mockups, the optional playlist
/// folders step and "¡Listo!".
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
            case .folders:
                PlaylistFoldersStepView(onAnswer: { enabled in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.answerPlaylistFolders(enabled: enabled)
                    }
                })
                .transition(.opacity)
            case .connected:
                SetupDoneView(onFinish: {
                    withAnimation(.easeInOut(duration: 0.4)) { appState.finishOnboarding() }
                })
                .transition(.opacity)
            }
        }
        // Steps changed by the login itself (Client ID → carpetas or ¡Listo!) also fade.
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func go(to step: AppState.OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.2)) {
            appState.dismissNotice()
            appState.showOnboardingStep(step)
        }
    }
}
