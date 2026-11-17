import SwiftUI

/// Setup · Carpetas de playlists (asked once, right after the first login).
///
/// Spotify's Web API does not return playlist folders. Nowdeck can read them from the
/// playlist service Spotify's own apps use, which Spotify does not document nor approve for
/// third-party apps. The owner decided to offer it as an **opt-in**, explained here, with
/// "seguir sin carpetas" as the main action. It can be changed later in Ajustes.
struct PlaylistFoldersStepView: View {
    let onAnswer: (_ enabled: Bool) -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        OnboardingScreen(topPadding: 60) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack {
                    Spacer()
                    Text("OPCIONAL")
                        .textStyle(.label)
                        .foregroundStyle(theme.palette.label.color)
                }
                .frame(minHeight: Metrics.minTouchTarget)

                Text("Carpetas de playlists")
                    .textStyle(.stepTitle)
                    .foregroundStyle(theme.palette.text.color)
                    .accessibilityAddTraits(.isHeader)

                Text("Spotify no les muestra tus carpetas a las apps como Nowdeck: la biblioteca muestra tus playlists sueltas, sin agrupar.")
                    .textStyle(.body)
                    .foregroundStyle(theme.palette.bodyText.color)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Hay una forma no oficial de leerlas: pedírselas al servicio que usa la propia app de Spotify, con tu misma sesión.")
                    .textStyle(.body)
                    .foregroundStyle(theme.palette.bodyText.color)
                    .fixedSize(horizontal: false, vertical: true)

                OnboardingCheckList(title: "ANTES DE ACTIVARLA") {
                    warning("Spotify no la aprueba para apps de terceros.")
                    warning("Puede dejar de andar en cualquier momento, sin aviso.")
                    warning("Si Spotify la detecta, podría bloquear el Client ID de tu app.")
                }
            }
        } footer: {
            VStack(spacing: Spacing.m) {
                Button("Seguir sin carpetas") { onAnswer(false) }
                    .buttonStyle(.primary)
                Button("Activar carpetas (experimental)") { onAnswer(true) }
                    .buttonStyle(.outline)
                Text("Lo podés cambiar cuando quieras en Ajustes → Reproductor.")
                    .textStyle(.footnote)
                    .foregroundStyle(theme.palette.label.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func warning(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.palette.warning.color)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .textStyle(.listItem)
                .foregroundStyle(theme.palette.text.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
