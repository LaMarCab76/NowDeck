import XCTest
@testable import Nowdeck

final class ThemeContrastTests: XCTestCase {
    private func color(_ hex: String) -> RGBColor { RGBColor(hex: hex)! }

    // MARK: WCAG math

    func testKnownRatios() {
        XCTAssertEqual(RGBColor.black.contrastRatio(with: .white), 21, accuracy: 0.001)
        XCTAssertEqual(color("#777777").contrastRatio(with: color("#777777")), 1, accuracy: 0.001)
        // Symmetric.
        XCTAssertEqual(color("#2FD566").contrastRatio(with: .black),
                       RGBColor.black.contrastRatio(with: color("#2FD566")), accuracy: 0.0001)
        // Values from docs/02-diseno.md ("Contrastes verificados sobre #34465A").
        let playerBackground = color("#34465A")
        XCTAssertEqual(color("#F2EEE8").contrastRatio(with: playerBackground), 8.4, accuracy: 0.05)
        XCTAssertEqual(color("#D5DCE4").contrastRatio(with: playerBackground), 7.0, accuracy: 0.05)
        XCTAssertEqual(color("#A9B4C0").contrastRatio(with: playerBackground), 4.6, accuracy: 0.05)
        XCTAssertEqual(color("#2FD566").contrastRatio(with: playerBackground), 5.0, accuracy: 0.05)
    }

    func testRatioIsFormattedWithCommaAndRoundedDown() {
        let spanish = Locale(identifier: "es")
        XCTAssertEqual(ThemeContrast.formattedRatio(4.31, locale: spanish), "4,3:1")
        // 4,49 must not look like it passes 4,5:1.
        XCTAssertEqual(ThemeContrast.formattedRatio(4.49, locale: spanish), "4,4:1")
        XCTAssertEqual(ThemeContrast.formattedRatio(21, locale: spanish), "21,0:1")
        // The app UI is Spanish, so the default locale formats the same way.
        XCTAssertEqual(ThemeContrast.formattedRatio(2.96), "2,9:1")
    }

    // MARK: fix(_:against:minimum:)

    func testColorThatAlreadyPassesIsNotTouched() {
        XCTAssertNil(ThemeContrast.fix(color("#F2EEE8"), against: [.black], minimum: 4.5))
    }

    func testLightensOnDarkBackgroundsInSmallSteps() throws {
        let original = color("#555555")
        let fix = try XCTUnwrap(ThemeContrast.fix(original, against: [.black], minimum: 4.5))
        XCTAssertEqual(fix.adjustment, .lighten)
        let ratio = fix.color.contrastRatio(with: .black)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
        // Just past the minimum, not jumped to white.
        XCTAssertLessThan(ratio, 4.9)
        XCTAssertGreaterThan(fix.color.relativeLuminance, original.relativeLuminance)
    }

    func testDarkensOnLightBackgrounds() throws {
        let fix = try XCTUnwrap(ThemeContrast.fix(color("#BBBBBB"), against: [.white], minimum: 4.5))
        XCTAssertEqual(fix.adjustment, .darken)
        XCTAssertGreaterThanOrEqual(fix.color.contrastRatio(with: .white), 4.5)
    }

    func testFixesAgainstSeveralBackgroundsAtOnce() throws {
        let fix = try XCTUnwrap(ThemeContrast.fix(color("#666666"),
                                                  against: [color("#000000"), color("#3A3A3A")],
                                                  minimum: 4.5))
        XCTAssertGreaterThanOrEqual(fix.color.contrastRatio(with: color("#000000")), 4.5)
        XCTAssertGreaterThanOrEqual(fix.color.contrastRatio(with: color("#3A3A3A")), 4.5)
    }

    func testCorrectedColorsAreWholeBytes() throws {
        let fix = try XCTUnwrap(ThemeContrast.fix(color("#8A6F7A"), against: [color("#120A0F")],
                                                  minimum: 4.5))
        XCTAssertEqual(RGBColor(hex: fix.color.hexString), fix.color)
    }

    // MARK: corrected(_:)

    func testDefaultThemeNeedsNoCorrection() throws {
        let colors = try XCTUnwrap(ThemeColorSet(Theme.default.colors))
        let result = ThemeContrast.corrected(colors)
        XCTAssertEqual(result.colors, colors)
        XCTAssertEqual(result.issues, [])
    }

    func testOnlyTheForegroundOfEachPairMoves() throws {
        var colors = try XCTUnwrap(ThemeColorSet(Theme.default.colors))
        colors.secondaryText = color("#333333")
        let result = ThemeContrast.corrected(colors)
        XCTAssertEqual(result.colors.background, colors.background)
        XCTAssertEqual(result.colors.text, colors.text)
        XCTAssertEqual(result.colors.accent, colors.accent)
        XCTAssertNotEqual(result.colors.secondaryText, colors.secondaryText)
        XCTAssertEqual(result.issues.map(\.check), [.secondaryTextOnBackground])
    }

    func testTextOnAccentIsCheckedAgainstTheCorrectedAccent() throws {
        var colors = try XCTUnwrap(ThemeColorSet(Theme.default.colors))
        // An accent too close to the black background, and text on it that only works with
        // the original (dark) accent.
        colors.accent = color("#202020")
        colors.textOnAccent = color("#B0B0B0")
        let result = ThemeContrast.corrected(colors)
        XCTAssertGreaterThanOrEqual(result.colors.accent.contrastRatio(with: colors.background), 3)
        XCTAssertGreaterThanOrEqual(result.colors.textOnAccent.contrastRatio(with: result.colors.accent), 4.5)
    }

    /// Random themes: after correction every rule holds (the text rule needs one color that
    /// works on both background and surface, which exists unless they are very different).
    func testRandomThemesAlwaysMeetTheRulesAfterCorrection() {
        var generator = SeededGenerator(seed: 7)
        func randomColor() -> RGBColor {
            RGBColor(hex: String(format: "#%06X", Int.random(in: 0...0xFFFFFF, using: &generator)))!
        }
        for _ in 0..<500 {
            let background = randomColor()
            // Surfaces are close to the background in real themes.
            let surface = background.mixed(with: Bool.random(using: &generator) ? .white : .black,
                                           amount: 0.08)
            let colors = ThemeColorSet(background: background, surface: surface,
                                       text: randomColor(), secondaryText: randomColor(),
                                       accent: randomColor(), textOnAccent: randomColor())
            let fixed = ThemeContrast.corrected(colors).colors
            XCTAssertGreaterThanOrEqual(fixed.accent.contrastRatio(with: fixed.background), 3)
            XCTAssertGreaterThanOrEqual(fixed.textOnAccent.contrastRatio(with: fixed.accent), 4.5)
            XCTAssertGreaterThanOrEqual(fixed.secondaryText.contrastRatio(with: fixed.background), 4.5)
            let bestText = max(min(RGBColor.white.contrastRatio(with: background),
                                   RGBColor.white.contrastRatio(with: surface)),
                               min(RGBColor.black.contrastRatio(with: background),
                                   RGBColor.black.contrastRatio(with: surface)))
            if bestText >= 4.5 {
                XCTAssertGreaterThanOrEqual(fixed.text.contrastRatio(with: fixed.background), 4.5)
                XCTAssertGreaterThanOrEqual(fixed.text.contrastRatio(with: fixed.surface), 4.5)
            }
        }
    }
}

extension ThemeColorSet {
    init(background: RGBColor, surface: RGBColor, text: RGBColor, secondaryText: RGBColor,
         accent: RGBColor, textOnAccent: RGBColor) {
        self.init(Theme.Colors(background: background.hexString, surface: surface.hexString,
                               text: text.hexString, secondaryText: secondaryText.hexString,
                               accent: accent.hexString, textOnAccent: textOnAccent.hexString))!
    }
}

/// Deterministic random numbers (SplitMix64), so a failure can be reproduced.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
