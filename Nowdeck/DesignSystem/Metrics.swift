import CoreGraphics

/// Spacing values shared across screens (points, on the 896×414 reference canvas).
/// Screen-specific measurements live next to each screen; only shared ones are here.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 48

    /// Player screen margins (docs/02-diseno.md, "Reproducción").
    enum Player {
        /// 24 in the mockup; 16 since the origin row sits above the artwork (its 44 pt tap
        /// zone keeps the text about 26 pt from the edge).
        static let top: CGFloat = 16
        static let horizontal: CGFloat = 48
        static let bottom: CGFloat = 20
        /// Vertical gap between the top block and the bottom block.
        static let blockGap: CGFloat = 20
    }
}

/// Corner radii (docs/02-diseno.md, "Formas y movimiento").
/// Pill buttons use `Capsule()`, so their radius is always half the height.
enum Radius {
    /// Spotify artwork. Never change it: required by Spotify's guidelines.
    static let artwork: CGFloat = 4
    static let row: CGFloat = 12
    static let card: CGFloat = 16
    /// Top corners of sheets.
    static let sheet: CGFloat = 20
}

/// Other shared sizes.
enum Metrics {
    /// Minimum tap target.
    static let minTouchTarget: CGFloat = 44
    /// Stroke width for line icons.
    static let iconStroke: CGFloat = 2
}
