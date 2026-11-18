import SwiftUI

/// The volume bar: bar · value, or why the volume can't change.
///
/// Since 2026-11-18 (owner's request, mockup `VolumenLateral.html`) it opens sideways inside
/// the controls row, out of the speaker button (`PlayerControls`), with no panel behind it
/// and without − and +: the bar takes a tap or a drag anywhere, and VoiceOver still moves it
/// 5 % per swipe. `PlayerControls` places it, sizes it and animates it; this view only draws
/// the content. While hidden it takes no touches and VoiceOver skips it.
struct VolumePanelView: View {
    @ObservedObject var volume: VolumeController

    @EnvironmentObject private var theme: ThemeStore
    /// Waits before announcing, so a burst of changes is read once, with the final level.
    @State private var announcementTask: Task<Void, Never>?
    /// Last time VoiceOver changed the level by swiping on the bar. VoiceOver reads the new
    /// value itself in that case, so no announcement follows.
    @State private var lastAdjustment = Date.distantPast
    /// While the finger moves on the bar, the fill follows it without animation. A gesture
    /// state goes back to `false` by itself also when the system cancels the gesture (an
    /// alert, a call), when `onEnded` is not called.
    @GestureState private var isDragging = false
    private typealias Layout = Metrics.VolumePanel

    /// How long the announcement waits for the changes to settle.
    static let announcementDelay: TimeInterval = 0.5

    var body: some View {
        HStack(spacing: Layout.gap) {
            if volume.isAdjustable, let level = volume.level {
                levelBar(level)
                Text(verbatim: String(level))
                    .textStyle(.volumeValue)
                    .foregroundStyle(theme.palette.text.color)
                    .frame(width: Layout.valueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            } else {
                // Two lines if needed: on the iPhone 8 Plus the room is about 270 pt.
                Text(unavailableMessage)
                    .textStyle(.volumeUnavailable)
                    .foregroundStyle(theme.palette.tertiaryText.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, Layout.leadingGap)
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
                    .updating($isDragging) { _, isDragging, _ in isDragging = true }
                    .onChanged { drag in
                        volume.drag(to: Self.level(atX: drag.location.x, width: proxy.size.width))
                    }
                    .onEnded { drag in
                        volume.drag(to: Self.level(atX: drag.location.x, width: proxy.size.width))
                        volume.endDrag()
                    }
            )
            // Covers a cancelled gesture, so the panel can hide again. After a normal lift
            // `endDrag()` already ran and this second call does nothing.
            .onChange(of: isDragging) { dragging in
                if !dragging { volume.endDrag() }
            }
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
}
