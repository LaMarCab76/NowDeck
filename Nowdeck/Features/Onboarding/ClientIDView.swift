import SwiftUI
import UIKit

/// Onboarding 3 · Pegar el Client ID (Onboarding3.dc.html).
struct ClientIDView: View {
    let onBack: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeStore

    @State private var clientID = ""
    @FocusState private var isFieldFocused: Bool

    private var isValid: Bool { ClientID.isValid(clientID) }

    var body: some View {
        OnboardingScreen(topPadding: 60) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                OnboardingStepHeader(stepLabel: "PASO 2 DE 2", onBack: onBack)

                Text("Pegá tu Client ID")
                    .textStyle(.stepTitle)
                    .foregroundStyle(theme.palette.text.color)
                    .accessibilityAddTraits(.isHeader)

                field

                permissions
            }
        } footer: {
            VStack(spacing: 14) {
                if let notice = appState.notice {
                    NoticeView(message: notice.message)
                }

                Button {
                    isFieldFocused = false
                    Task { await appState.connect(clientID: clientID) }
                } label: {
                    if appState.isConnecting {
                        HStack(spacing: Spacing.xs) {
                            ProgressView()
                                .tint(theme.palette.textOnAccent.color)
                            Text("Conectando…")
                        }
                    } else {
                        Text("Conectar con Spotify")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!isValid || appState.isConnecting)

                Text("Se abre el inicio de sesión de Spotify. Después volvés solo a Nowdeck.")
                    .textStyle(.footnote)
                    .foregroundStyle(theme.palette.label.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            // After an expired session, the stored ID is prefilled.
            if clientID.isEmpty, let saved = appState.savedClientID {
                clientID = saved
            }
        }
    }

    // MARK: Field

    private var field: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("CLIENT ID")
                .textStyle(.label)
                .foregroundStyle(theme.palette.label.color)
                .accessibilityHidden(true)

            HStack(spacing: Spacing.xs) {
                TextField(text: $clientID) {
                    Text("Pegalo acá")
                        .foregroundColor(theme.palette.label.color)
                }
                .textStyle(.codeInput)
                .foregroundStyle(theme.palette.text.color)
                .tint(theme.palette.accent.color)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(nil)
                .submitLabel(.go)
                .focused($isFieldFocused)
                .accessibilityLabel(Text("Client ID"))
                .onSubmit {
                    Task { await appState.connect(clientID: clientID) }
                }
                .onChange(of: clientID) { newValue in
                    // Strip the spaces and line breaks that come with copied text.
                    let normalized = ClientID.normalized(newValue)
                    if normalized != newValue { clientID = normalized }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .fill(theme.palette.surface.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(isFieldFocused ? theme.palette.accent.color : Palette.outline.color,
                                      lineWidth: 1)
                )

                Button("Pegar", action: paste)
                    .buttonStyle(SubtleButtonStyle(height: 56, cornerRadius: Radius.row,
                                                   horizontalPadding: 18,
                                                   textStyle: .secondaryButton))
            }

            helperText
        }
    }

    @ViewBuilder
    private var helperText: some View {
        if !clientID.isEmpty && !isValid {
            Label {
                Text("Tiene que tener 32 letras y números, y ahora tiene \(clientID.count) caracteres. Revisá que lo hayas copiado completo.")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.palette.warning.color)
            }
            .textStyle(.helper)
            .foregroundStyle(theme.palette.bodyText.color)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Son 32 letras y números. Se guarda solo en este iPhone, en el Llavero.")
                .textStyle(.helper)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Permissions

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            OnboardingCheckList(title: "NOWDECK VA A PEDIR PERMISO PARA") {
                OnboardingCheckItem(text: "Ver qué está sonando y qué escuchaste último")
                OnboardingCheckItem(text: "Pausar, saltar temas y cambiar el volumen")
                OnboardingCheckItem(text: "Ver tus dispositivos y pasar la música de uno a otro")
                OnboardingCheckItem(text: "Ver tus playlists, álbumes, podcasts y audiolibros guardados")
            }
            Text("No ve tu contraseña ni toca tus playlists.")
                .textStyle(.helper)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.s)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.divider.color)
                .frame(height: 1)
        }
    }

    // MARK: Actions

    /// Reading the pasteboard from code makes iOS ask "Allow Paste?" each time. The field
    /// itself also accepts a long-press paste, which does not ask.
    private func paste() {
        guard let text = UIPasteboard.general.string else { return }
        clientID = ClientID.normalized(text)
    }
}

/// A warning shown above the main button after a failed login.
private struct NoticeView: View {
    let message: LocalizedStringResource
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.palette.warning.color)
                .accessibilityHidden(true)
            Text(message)
                .textStyle(.helper)
                .foregroundStyle(theme.palette.text.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(theme.palette.surface.color)
        )
        .accessibilityElement(children: .combine)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: String(localized: message))
        }
    }
}
