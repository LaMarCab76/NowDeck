import SwiftUI

/// Onboarding 1 · Bienvenida (Onboarding1.dc.html).
struct WelcomeView: View {
    let onStart: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        OnboardingScreen(topPadding: 72) {
            HStack(spacing: 10) {
                NowdeckLogo()
                Text(verbatim: "Nowdeck")
                    .textStyle(.brandName)
                    .foregroundStyle(theme.palette.text.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } middle: {
            VStack(alignment: .leading, spacing: 22) {
                DeckIllustration()

                Text("Tu iPhone, ahora control de escritorio.")
                    .textStyle(.welcomeTitle)
                    .foregroundStyle(theme.palette.text.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Nowdeck maneja la música de cualquier dispositivo con tu cuenta de Spotify. Para eso necesita una app de desarrollador tuya: se crea una sola vez y lleva unos 5 minutos.")
                    .textStyle(.body)
                    .foregroundStyle(theme.palette.bodyText.color)
                    .fixedSize(horizontal: false, vertical: true)

                OnboardingCheckList(title: "VAS A NECESITAR") {
                    OnboardingCheckItem(text: "Spotify Premium")
                    OnboardingCheckItem(text: "Un navegador para entrar al panel de desarrolladores de Spotify")
                    OnboardingCheckItem(text: "5 minutos")
                }
            }
        } footer: {
            VStack(spacing: Spacing.m) {
                Button("Empezar", action: onStart)
                    .buttonStyle(.primary)

                Text("Nowdeck es un proyecto open source independiente. No está afiliado a Spotify ni cuenta con su aval.")
                    .textStyle(.footnote)
                    .foregroundStyle(theme.palette.label.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
