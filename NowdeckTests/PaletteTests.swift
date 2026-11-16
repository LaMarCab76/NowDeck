import XCTest
@testable import Nowdeck

final class PaletteTests: XCTestCase {
    /// Token values from docs/02-diseno.md, "Colores (tema por defecto)".
    func testDefaultPaletteMatchesDesignTokens() {
        let palette = Palette.default
        XCTAssertEqual(palette.background.hexString, "#000000")
        XCTAssertEqual(palette.surface.hexString, "#161616")
        XCTAssertEqual(palette.text.hexString, "#F2EEE8")
        XCTAssertEqual(palette.secondaryText.hexString, "#D5DCE4")
        XCTAssertEqual(palette.tertiaryText.hexString, "#A9B4C0")
        XCTAssertEqual(palette.bodyText.hexString, "#C9C4BC")
        XCTAssertEqual(palette.label.hexString, "#A39D95")
        XCTAssertEqual(palette.pendingLyric.hexString, "#8E99A6")
        XCTAssertEqual(palette.accent.hexString, "#2FD566")
        XCTAssertEqual(palette.textOnAccent.hexString, "#00170A")
        XCTAssertEqual(palette.warning.hexString, "#FFB23E")
    }

    /// Agreed mapping: the theme's `textoSecundario` drives the design's `textoTerciario`.
    func testThemeSecondaryTextDrivesTertiaryToken() {
        var theme = Theme.default
        theme.colors?.secondaryText = "#123456"
        let palette = Palette(theme: theme)
        XCTAssertEqual(palette.tertiaryText.hexString, "#123456")
        XCTAssertEqual(palette.secondaryText.hexString, "#D5DCE4")
    }

    func testMissingOrInvalidColorsFallBackToDefault() {
        let theme = Theme(
            format: Theme.currentFormat,
            name: "Parcial",
            colors: Theme.Colors(background: "#0B1220", accent: "not-a-color")
        )
        let palette = Palette(theme: theme)
        XCTAssertEqual(palette.background.hexString, "#0B1220")
        XCTAssertEqual(palette.accent.hexString, "#2FD566")
        XCTAssertEqual(palette.text.hexString, "#F2EEE8")
    }

    func testThemeWithoutColorsUsesDefaultPalette() {
        let theme = Theme(format: Theme.currentFormat, name: "Sin colores")
        XCTAssertEqual(Palette(theme: theme), Palette.default)
    }
}
