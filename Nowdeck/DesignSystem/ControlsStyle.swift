import SwiftUI

// Design tokens of the player controls (milestone 3): the volume bar, the ±15 s buttons and
// the disabled state. In their own file so the shared design system files stay untouched.

extension Metrics {
    /// The volume bar that opens sideways in the controls row (owner's request, 2026-11-18,
    /// mockup `VolumenLateral.html`). It replaced the 520×64 floating pill of
    /// `Volumen.dc.html`, and with it the dark panel, the shadow and the − and + buttons.
    enum VolumePanel {
        /// Between the speaker button and the bar.
        static let leadingGap: CGFloat = 12
        /// Between the bar and the value.
        static let gap: CGFloat = 12
        static let barHeight: CGFloat = 8
        /// The number at the right of the bar (`width: 30px; text-align: right`).
        static let valueWidth: CGFloat = 30
    }

    /// The ±15 s buttons that replace previous/next for podcast episodes. Same 56 pt circle
    /// as previous/next; the SF Symbol with the number needs a slightly smaller glyph than
    /// the 28 pt of the skip arrows to read as the same size.
    enum SeekButton {
        static let iconSize: CGFloat = 26
    }
}

extension Palette {
    /// Bar track: white at 14 %.
    static let volumeTrack = Color.white.opacity(0.14)
    /// Controls that `actions.disallows` (or a restricted device) forbids. The mockups have no
    /// disabled state; this keeps the icon visible but clearly inactive.
    static let disabledControlOpacity = 0.35
}

extension TextStyle {
    /// The level next to the bar: monospaced 14/18.
    static let volumeValue = TextStyle(size: 14, weight: .regular, design: .monospaced,
                                       lineHeight: 18, scalesWithDynamicType: false)
    /// "Este dispositivo no permite cambiar el volumen" in place of the bar.
    static let volumeUnavailable = TextStyle(size: 14, weight: .medium, lineHeight: 18,
                                             scalesWithDynamicType: false)
}

/// Timings of the volume bar (docs/02-diseno.md, "Barra de volumen").
enum VolumePanelMotion {
    /// Opening (the row moves and the bar unrolls): 0.30 s with `cubic-bezier(0.2, 0.8, 0.2, 1)`.
    static let entry = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)
    /// Closing: 0.22 s ease-in.
    static let exit = Animation.easeIn(duration: 0.22)
    /// What appears: the bar's content when it opens, and the controls that come back when
    /// it closes. It starts a little late, so it shows up once there is room.
    static let fadeIn = Animation.easeOut(duration: 0.2).delay(0.06)
    /// What leaves: the controls that make room for the bar, and the bar's content when it
    /// closes.
    static let fadeOut = Animation.easeOut(duration: 0.12)
    /// Bar fill: `transition: width 0.15s ease` (CSS `ease` is `cubic-bezier(.25,.1,.25,1)`).
    static let level = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.15)
}
