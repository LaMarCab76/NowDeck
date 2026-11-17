import SwiftUI
import UIKit

/// The pill shown for 3 s when a command fails. Same look and place as the "no lyrics"
/// notice (docs/02-diseno.md, "Aviso"): `texto` background, dark text in 15 semibold, an
/// icon, 20 pt from the top, announced to VoiceOver.
struct ControlNoticeView: View {
    let notice: PlayerControlsModel.Notice
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: Metrics.Notice.iconSpacing) {
            Image(systemName: iconName)
                .font(.system(size: Metrics.Notice.iconSize - 3, weight: .semibold))
                .frame(width: Metrics.Notice.iconSize, height: Metrics.Notice.iconSize)
                .accessibilityHidden(true)
            Text(message)
                .textStyle(.notice)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Palette.noticeForeground)
        .padding(.leading, Metrics.Notice.leadingPadding)
        .padding(.trailing, Metrics.Notice.trailingPadding)
        .frame(height: Metrics.Notice.height)
        .background(Capsule().fill(theme.palette.text.color))
        .shadow(color: Palette.noticeShadow, radius: Metrics.Notice.shadowRadius,
                y: Metrics.Notice.shadowY)
        .accessibilityElement(children: .combine)
        .onAppear { announce() }
        .onChange(of: notice) { _ in announce() }
    }

    private func announce() {
        UIAccessibility.post(notification: .announcement, argument: String(localized: message))
    }

    private var iconName: String {
        switch notice {
        case .noActiveDevice: return "hifispeaker"
        case .notAllowed, .rateLimited, .failed: return "exclamationmark.circle"
        }
    }

    private var message: LocalizedStringResource {
        switch notice {
        case .notAllowed:
            return "Spotify no aceptó el comando. Revisá que tu cuenta tenga Premium."
        case .noActiveDevice:
            return "No hay un dispositivo activo. Elegí uno para seguir."
        case .rateLimited:
            return "Spotify pide esperar. Probá de nuevo en un momento."
        case .failed:
            return "No pudimos mandar el comando. Probá de nuevo."
        }
    }
}
