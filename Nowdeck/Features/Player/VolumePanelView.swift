import SwiftUI

/// The floating volume pill (`Main.dc.html`, shown in `Volumen.dc.html`):
/// [−] · speaker · bar · value · [+].
///
/// It is always in the hierarchy and slides between `y = −112` (hidden, above the screen) and
/// its place 16 pt from the top, so the entry and exit animate like the mockup's
/// `translateY`. While hidden it takes no touches and VoiceOver skips it.
struct VolumePanelView: View {
    @ObservedObject var volume: VolumeController

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.VolumePanel

    var body: some View {
        HStack(spacing: Layout.gap) {
            stepButton(systemName: "minus", label: "Bajar volumen", action: volume.decrease)

            Image(systemName: "speaker.wave.2")
                .font(.system(size: Layout.speakerIconSize - 3, weight: .medium))
                .foregroundStyle(theme.palette.tertiaryText.color)
                .frame(width: Layout.speakerIconSize, height: Layout.speakerIconSize)
                .accessibilityHidden(true)

            if volume.isAdjustable, let level = volume.level {
                levelBar(level)
                Text(verbatim: String(level))
                    .textStyle(.volumeValue)
                    .foregroundStyle(theme.palette.text.color)
                    .frame(width: Layout.valueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            } else {
                Text(unavailableMessage)
                    .textStyle(.volumeUnavailable)
                    .foregroundStyle(theme.palette.tertiaryText.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            stepButton(systemName: "plus", label: "Subir volumen", action: volume.increase)
        }
        .padding(Layout.padding)
        .frame(width: Layout.width, height: Layout.height)
        .background(Capsule().fill(Palette.volumePanelBackground))
        .shadow(color: Palette.volumePanelShadow, radius: Layout.shadowRadius, y: Layout.shadowY)
        .padding(.top, Layout.top)
        .offset(y: volume.isPanelVisible ? 0 : Layout.hiddenOffset)
        .animation(volume.isPanelVisible ? VolumePanelMotion.entry : VolumePanelMotion.exit,
                   value: volume.isPanelVisible)
        .allowsHitTesting(volume.isPanelVisible)
        .accessibilityHidden(!volume.isPanelVisible)
    }

    private var unavailableMessage: LocalizedStringKey {
        volume.hasDevice ? "Este dispositivo no permite cambiar el volumen"
                         : "No hay un dispositivo activo"
    }

    private func levelBar(_ level: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.volumeTrack)
                Capsule()
                    .fill(theme.palette.accent.color)
                    .frame(width: proxy.size.width * CGFloat(level) / 100)
                    .animation(VolumePanelMotion.level, value: level)
            }
        }
        .frame(height: Layout.barHeight)
        .accessibilityElement()
        .accessibilityLabel(Text("Volumen"))
        .accessibilityValue(Text("\(level) de 100"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: volume.increase()
            case .decrement: volume.decrease()
            @unknown default: break
            }
        }
    }

    private func stepButton(systemName: String, label: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Layout.buttonIconSize, weight: .semibold))
                .foregroundStyle(theme.palette.text.color)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .background(Circle().fill(Palette.volumeButtonBackground))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!volume.isAdjustable)
        .opacity(volume.isAdjustable ? 1 : Palette.disabledControlOpacity)
        .accessibilityLabel(Text(label))
    }
}
