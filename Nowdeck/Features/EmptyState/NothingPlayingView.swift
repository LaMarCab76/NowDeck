import SwiftUI

/// "Nada sonando" (`SinReproduccion.dc.html`), and two error states that reuse its layout.
struct NothingPlayingView: View {
    enum Kind: Equatable {
        /// Nothing is playing on any device.
        case nothingPlaying
        /// `403` from the API: the account cannot use this app.
        case accessDenied
        /// The first poll failed: no connection or Spotify is down.
        case unavailable
    }

    var kind: Kind
    /// "Elegir dispositivo" (opens Dispositivos in milestone 4).
    var chooseDevice: () -> Void = {}

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.EmptyState

    var body: some View {
        HStack(spacing: Layout.columnGap) {
            placeholderFrame
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                VStack(alignment: .leading, spacing: Layout.titleBodyGap) {
                    Text(title)
                        .textStyle(.emptyTitle)
                        .foregroundStyle(theme.palette.text.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .textStyle(.emptyBody)
                        .foregroundStyle(theme.palette.bodyText.color)
                        .frame(maxWidth: Layout.bodyMaxWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buttons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    /// The dashed frame where the artwork would be.
    private var placeholderFrame: some View {
        RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous)
            .strokeBorder(Palette.emptyArtworkBorder,
                          style: StrokeStyle(lineWidth: Layout.frameBorderWidth,
                                             dash: Layout.frameDash))
            .overlay(
                Image(systemName: kind == .accessDenied ? "lock" : "music.note")
                    .font(.system(size: Layout.iconSize * 0.75, weight: .ultraLight))
                    .foregroundStyle(theme.palette.label.color)
            )
            .frame(width: Layout.frameSize, height: Layout.frameSize)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: Layout.buttonsGap) {
            switch kind {
            case .nothingPlaying:
                Button("Elegir dispositivo", action: chooseDevice)
                    .buttonStyle(CompactPrimaryButtonStyle())
                openSpotifyLink
            case .accessDenied:
                Button("Abrir el panel de Spotify") {
                    UIApplication.shared.open(SpotifyDashboard.url)
                }
                .buttonStyle(CompactPrimaryButtonStyle())
            case .unavailable:
                openSpotifyLink
            }
        }
    }

    /// "ABRIR SPOTIFY ↗": the visible link the compliance checklist asks for.
    private var openSpotifyLink: some View {
        Button {
            SpotifyLink.open(SpotifyLink.home)
        } label: {
            HStack(spacing: Layout.linkIconGap) {
                Text("ABRIR SPOTIFY")
                    .textStyle(.openSpotifyLink)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: Layout.linkIconSize, weight: .bold))
            }
            .foregroundStyle(theme.palette.text.color)
            .frame(height: Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .nothingPlaying: return "Nada sonando"
        case .accessDenied: return "Spotify no deja usar tu app"
        case .unavailable: return "Sin conexión con Spotify"
        }
    }

    private var message: LocalizedStringKey {
        switch kind {
        case .nothingPlaying:
            return "Poné algo en Spotify en cualquiera de tus dispositivos y aparece acá."
        case .accessDenied:
            return "Revisá que tu cuenta siga en Users Management, en los ajustes de tu app en el panel de Spotify, y que la cuenta dueña de la app tenga Premium. Nowdeck vuelve a probar solo."
        case .unavailable:
            return "Revisá la conexión a internet. Nowdeck vuelve a probar solo."
        }
    }
}

/// Spotify's developer dashboard, where the user manages their app.
enum SpotifyDashboard {
    static let url = URL(string: "https://developer.spotify.com/dashboard")!
}

/// The accent capsule of "Elegir dispositivo": 56 pt high, 28 pt side padding, hugging its
/// text (the shared `PrimaryButtonStyle` fills the width, as onboarding needs).
struct CompactPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @EnvironmentObject private var theme: ThemeStore

        var body: some View {
            configuration.label
                .textStyle(.primaryButton)
                .foregroundStyle(theme.palette.textOnAccent.color)
                .lineLimit(1)
                .padding(.horizontal, Metrics.EmptyState.primaryButtonPadding)
                .frame(height: Metrics.EmptyState.primaryButtonHeight)
                .background(Capsule().fill(theme.palette.accent.color))
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}
