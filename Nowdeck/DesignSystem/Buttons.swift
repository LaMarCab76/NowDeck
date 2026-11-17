import SwiftUI

/// Main call to action: accent capsule, 56 pt high ("Empezar", "Conectar con Spotify").
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration)
    }

    private struct PrimaryButton: View {
        let configuration: ButtonStyleConfiguration
        @EnvironmentObject private var theme: ThemeStore
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .textStyle(.primaryButton)
                .foregroundStyle(theme.palette.textOnAccent.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(theme.palette.accent.color))
                .contentShape(Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
        }
    }
}

/// Secondary action: outlined capsule, 52 pt high ("Abrir el panel").
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OutlineButton(configuration: configuration)
    }

    private struct OutlineButton: View {
        let configuration: ButtonStyleConfiguration
        @EnvironmentObject private var theme: ThemeStore

        var body: some View {
            configuration.label
                .textStyle(.secondaryButton)
                .foregroundStyle(theme.palette.text.color)
                .padding(.horizontal, Spacing.l)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay(Capsule().strokeBorder(Palette.outlineButtonBorder, lineWidth: 1.5))
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

/// Small filled button on a translucent white rounded rectangle ("Copiar", "Pegar").
struct SubtleButtonStyle: ButtonStyle {
    var height: CGFloat = Metrics.minTouchTarget
    var cornerRadius: CGFloat = 8
    var horizontalPadding: CGFloat = 14
    var textStyle: TextStyle = .smallButton

    func makeBody(configuration: Configuration) -> some View {
        SubtleButton(configuration: configuration, style: self)
    }

    private struct SubtleButton: View {
        let configuration: ButtonStyleConfiguration
        let style: SubtleButtonStyle
        @EnvironmentObject private var theme: ThemeStore

        var body: some View {
            configuration.label
                .textStyle(style.textStyle)
                .foregroundStyle(theme.palette.text.color)
                .padding(.horizontal, style.horizontalPadding)
                .frame(minHeight: style.height)
                .background(
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.1))
                )
                .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius))
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
}

extension ButtonStyle where Self == SubtleButtonStyle {
    static var subtle: SubtleButtonStyle { SubtleButtonStyle() }
}
