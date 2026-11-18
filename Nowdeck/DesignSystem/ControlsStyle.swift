import SwiftUI

// Design tokens of the player controls (milestone 3): the volume panel from `Main.dc.html`
// (the absolutely positioned pill, shown by `Volumen.dc.html`), the ±15 s buttons and the
// disabled state. In their own file so the shared design system files stay untouched.

extension Metrics {
    /// Volume panel: `width 520, height 64, padding 8, gap 12, border-radius 32`. The mockup
    /// floats it 16 from the top; since 2026-11-18 it sits 16 from the bottom (owner's
    /// request).
    enum VolumePanel {
        static let width: CGFloat = 520
        static let height: CGFloat = 64
        /// Distance from the bottom of the screen.
        static let bottom: CGFloat = 16
        /// The rest of the player while the panel is open, scaled toward the top: on the
        /// 414 pt screen it leaves 92 pt below it, the panel's 64 + 16 plus a 12 pt gap
        /// (`(414 − 92) / 414 ≈ 0.78`).
        static let playerScale: CGFloat = 0.78
        static let padding: CGFloat = 8
        static let gap: CGFloat = 12
        /// − and + buttons.
        static let buttonSize: CGFloat = 48
        /// The − and + glyphs (22 pt box, 2.5 stroke in the mockup).
        static let buttonIconSize: CGFloat = 18
        static let speakerIconSize: CGFloat = 22
        static let barHeight: CGFloat = 8
        /// The number at the right of the bar (`width: 30px; text-align: right`).
        static let valueWidth: CGFloat = 30
        /// Hidden position: 112 below its place (the mockup's `translateY(-112px)`, flipped).
        static let hiddenOffset: CGFloat = 112
        /// `box-shadow: 0 10px 32px` → SwiftUI's radius is about half the CSS blur.
        static let shadowRadius: CGFloat = 16
        static let shadowY: CGFloat = 10
    }

    /// The ±15 s buttons that replace previous/next for podcast episodes. Same 56 pt circle
    /// as previous/next; the SF Symbol with the number needs a slightly smaller glyph than
    /// the 28 pt of the skip arrows to read as the same size.
    enum SeekButton {
        static let iconSize: CGFloat = 26
    }
}

extension Palette {
    /// Panel background: `rgba(8,10,14,0.94)`.
    static let volumePanelBackground = Color(red: 8 / 255, green: 10 / 255, blue: 14 / 255)
        .opacity(0.94)
    /// `0 10px 32px rgba(0,0,0,0.5)`.
    static let volumePanelShadow = Color.black.opacity(0.5)
    /// − and + circles: white at 10 %.
    static let volumeButtonBackground = Color.white.opacity(0.1)
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

/// Timings of the volume panel (docs/02-diseno.md, "Panel de volumen").
enum VolumePanelMotion {
    /// Entry: 0.30 s with `cubic-bezier(0.2, 0.8, 0.2, 1)`.
    static let entry = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)
    /// Exit: 0.22 s ease-in.
    static let exit = Animation.easeIn(duration: 0.22)
    /// Bar fill: `transition: width 0.15s ease` (CSS `ease` is `cubic-bezier(.25,.1,.25,1)`).
    static let level = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.15)
}
