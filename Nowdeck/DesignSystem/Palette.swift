import SwiftUI

/// The color tokens of docs/02-diseno.md, resolved for the active theme.
///
/// Token names (design doc → code):
///
/// | Design            | Code              | Comes from                         |
/// |-------------------|-------------------|------------------------------------|
/// | fondo             | background        | theme `fondo`                      |
/// | superficie        | surface           | theme `superficie`                 |
/// | texto             | text              | theme `texto`                      |
/// | textoSecundario   | secondaryText     | fixed `#D5DCE4`                    |
/// | textoTerciario    | tertiaryText      | theme `textoSecundario` (*)        |
/// | textoCuerpo       | bodyText          | fixed `#C9C4BC`                    |
/// | etiqueta          | label             | fixed `#A39D95`                    |
/// | letraPendiente    | pendingLyric      | fixed `#8E99A6`                    |
/// | acento            | accent            | theme `acento`                     |
/// | textoSobreAcento  | textOnAccent      | theme `textoSobreAcento`           |
/// | advertencia       | warning           | fixed `#FFB23E`                    |
/// | superficieSutil   | subtleSurface     | white at 9 %                       |
/// | bordeChip         | chipBorder        | white at 35 %                      |
///
/// (*) The theme format calls `textoSecundario` the color that the design names
/// `textoTerciario` (both `#A9B4C0` in the default theme). Agreed with the owner: the theme
/// value drives `tertiaryText`, and the design's `textoSecundario` stays fixed.
///
/// `fondoReproductor` (the artwork-derived background) is not here: it changes with every
/// track and is computed by the artwork service (milestone 2).
struct Palette: Equatable, Sendable {
    // Driven by the theme.
    var background: RGBColor
    var surface: RGBColor
    var text: RGBColor
    var tertiaryText: RGBColor
    var accent: RGBColor
    var textOnAccent: RGBColor

    // Fixed in theme format v1.
    var secondaryText = RGBColor(hex: "#D5DCE4")!
    var bodyText = RGBColor(hex: "#C9C4BC")!
    var label = RGBColor(hex: "#A39D95")!
    var pendingLyric = RGBColor(hex: "#8E99A6")!
    var warning = RGBColor(hex: "#FFB23E")!

    /// Translucent white for pill buttons, rows and the tab container (design: 7–10 %).
    /// Screens that need a specific value from the mockups (8 %, 10 %, 12 %) use
    /// `Color.white.opacity(_:)` directly with that value.
    static let subtleSurface = Color.white.opacity(0.09)
    /// Border of unselected filter chips.
    static let chipBorder = Color.white.opacity(0.35)
}

extension Palette {
    /// Builds the palette for a theme. Missing or malformed colors fall back to the default
    /// theme, so a partially specified theme still renders.
    init(theme: Theme) {
        let colors = theme.colors
        let fallback = Theme.default.colors!

        func resolve(_ value: String?, _ defaultValue: String?) -> RGBColor {
            if let value, let color = RGBColor(hex: value) { return color }
            return RGBColor(hex: defaultValue!)!
        }

        self.init(
            background: resolve(colors?.background, fallback.background),
            surface: resolve(colors?.surface, fallback.surface),
            text: resolve(colors?.text, fallback.text),
            tertiaryText: resolve(colors?.secondaryText, fallback.secondaryText),
            accent: resolve(colors?.accent, fallback.accent),
            textOnAccent: resolve(colors?.textOnAccent, fallback.textOnAccent)
        )
    }

    static let `default` = Palette(theme: .default)
}
