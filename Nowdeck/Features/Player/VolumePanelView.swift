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
    /// Waits before announcing, so a burst of taps on − or + is read once, with the final
    /// level.
    @State private var announcementTask: Task<Void, Never>?
    /// Last time VoiceOver changed the level by swiping on the bar. VoiceOver reads the new
    /// value itself in that case, so no announcement follows.
    @State private var lastAdjustment = Date.distantPast
    /// While the finger moves on the bar, the fill follows it without animation.
    @State private var isDragging = false
    private typealias Layout = Metrics.VolumePanel

    /// How long the announcement waits for the taps to settle.
    static let announcementDelay: TimeInterval = 0.5

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
        .onChange(of: volume.announcement) { announce($0) }
    }

    private func announce(_ announcement: VolumeAnnouncement?) {
        announcementTask?.cancel()
        guard let announcement,
              Date().timeIntervalSince(lastAdjustment) > Self.announcementDelay * 2 else { return }
        let delay = Self.announcementDelay
        announcementTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            AccessibilityAnnouncement.post(announcement.message)
        }
    }

    private var unavailableMessage: LocalizedStringKey {
        volume.hasDevice ? "Este dispositivo no permite cambiar el volumen"
                         : "No hay un dispositivo activo"
    }

    /// The bar is 6 pt high but the whole 44 pt row around it takes the finger: tap or drag
    /// anywhere on it to set the level.
    private func levelBar(_ level: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.volumeTrack)
                Capsule()
                    .fill(theme.palette.accent.color)
                    .frame(width: proxy.size.width * CGFloat(level) / 100)
                    .animation(isDragging ? nil : VolumePanelMotion.level, value: level)
            }
            .frame(height: Layout.barHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        volume.drag(to: Self.level(atX: drag.location.x, width: proxy.size.width))
                    }
                    .onEnded { drag in
                        volume.drag(to: Self.level(atX: drag.location.x, width: proxy.size.width))
                        volume.endDrag()
                        isDragging = false
                    }
            )
        }
        .frame(height: Metrics.minTouchTarget)
        .accessibilityElement()
        .accessibilityLabel(Text("Volumen"))
        .accessibilityValue(Text("\(level) de 100"))
        .accessibilityAdjustableAction { direction in
            lastAdjustment = Date()
            switch direction {
            case .increment: volume.increase()
            case .decrement: volume.decrease()
            @unknown default: break
            }
        }
    }

    /// The level under a finger at `x` on a bar `width` wide, rounded to whole percents.
    static func level(atX x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        return Int((min(max(x / width, 0), 1) * 100).rounded())
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
