import SwiftUI
import UIKit

/// Onboarding 2 · Crear la app en Spotify (Onboarding2.dc.html).
struct CreateAppView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    var body: some View {
        OnboardingScreen(topPadding: 60) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                OnboardingStepHeader(stepLabel: "PASO 1 DE 2", onBack: onBack)

                Text("Creá tu app en Spotify")
                    .textStyle(.stepTitle)
                    .foregroundStyle(theme.palette.text.color)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 18) {
                    NumberedStep(number: 1) {
                        StepText("Entrá a **developer.spotify.com/dashboard** con tu cuenta Premium.")
                    }
                    NumberedStep(number: 2) {
                        StepText("Tocá **Create app**. En nombre y descripción poné lo que quieras.")
                    }
                    NumberedStep(number: 3) {
                        VStack(alignment: .leading, spacing: 10) {
                            StepText("En **Redirect URIs** pegá esto, tal cual:")
                            RedirectURIBox()
                        }
                    }
                    NumberedStep(number: 4) {
                        StepText("Donde pregunta qué API vas a usar, marcá **Web API** y guardá.")
                    }
                    NumberedStep(number: 5) {
                        StepText("Abrí **Settings** y copiá el **Client ID**. El Client secret no hace falta.")
                    }
                }
            }
        } footer: {
            VStack(spacing: Spacing.s) {
                Link(destination: Self.dashboardURL) {
                    HStack(spacing: Spacing.xs) {
                        Text("Abrir el panel")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.outline)

                Button("Ya tengo mi Client ID", action: onContinue)
                    .buttonStyle(.primary)
            }
        }
    }
}

/// A numbered instruction: 28 pt circle with the number, then the content.
private struct NumberedStep<Content: View>: View {
    let number: Int
    @ViewBuilder var content: Content
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: "\(number)")
                .textStyle(.stepNumber)
                .foregroundStyle(theme.palette.text.color)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Palette.outline.color, lineWidth: 1.5))
                .accessibilityHidden(true)
            content
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Body text of a step. Bold parts come from Markdown in the localized string.
private struct StepText: View {
    let key: LocalizedStringKey
    @EnvironmentObject private var theme: ThemeStore

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .textStyle(.body)
            .foregroundStyle(theme.palette.text.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `nowdeck://callback` with a Copy button.
private struct RedirectURIBox: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: SpotifyAuthorization.redirectURI)
                .textStyle(.code)
                .foregroundStyle(theme.palette.accent.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button {
                copy()
            } label: {
                Text(didCopy ? "Copiado" : "Copiar")
            }
            .buttonStyle(.subtle)
            .accessibilityHint(Text("Copia el Redirect URI"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(theme.palette.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
    }

    private func copy() {
        UIPasteboard.general.string = SpotifyAuthorization.redirectURI
        didCopy = true
        UIAccessibility.post(notification: .announcement,
                             argument: String(localized: "Copiado"))
        // Back to "Copiar" after a moment, so a second tap still gives feedback.
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}
