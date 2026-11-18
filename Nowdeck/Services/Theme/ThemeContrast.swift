import Foundation

// MARK: - WCAG 2.x math

extension RGBColor {
    static let white = RGBColor(red: 1, green: 1, blue: 1)
    static let black = RGBColor(red: 0, green: 0, blue: 0)

    /// Relative luminance as defined by WCAG 2.x (sRGB, linearized).
    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, from 1 (same luminance) to 21 (black on white).
    func contrastRatio(with other: RGBColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Linear mix in sRGB: `amount` 0 returns `self`, 1 returns `other`. The result is rounded
    /// to 8 bits per channel, so what we measure is exactly what `hexString` will store.
    func mixed(with other: RGBColor, amount: Double) -> RGBColor {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        let raw = RGBColor(red: mix(red, other.red), green: mix(green, other.green),
                           blue: mix(blue, other.blue))
        return RGBColor(hex: raw.hexString)!
    }
}

// MARK: - Theme colors as RGB

/// The six theme colors, parsed. Names follow the theme format (`secondaryText` is the
/// theme's `textoSecundario`, which the palette shows as `tertiaryText`).
struct ThemeColorSet: Equatable, Sendable {
    var background: RGBColor
    var surface: RGBColor
    var text: RGBColor
    var secondaryText: RGBColor
    var accent: RGBColor
    var textOnAccent: RGBColor

    /// Fails if any color is missing or malformed. Use it on a theme merged with the default.
    init?(_ colors: Theme.Colors?) {
        guard let colors,
              let background = colors.background.flatMap(RGBColor.init(hex:)),
              let surface = colors.surface.flatMap(RGBColor.init(hex:)),
              let text = colors.text.flatMap(RGBColor.init(hex:)),
              let secondaryText = colors.secondaryText.flatMap(RGBColor.init(hex:)),
              let accent = colors.accent.flatMap(RGBColor.init(hex:)),
              let textOnAccent = colors.textOnAccent.flatMap(RGBColor.init(hex:))
        else { return nil }
        self.background = background
        self.surface = surface
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
        self.textOnAccent = textOnAccent
    }

    /// Uppercase `#RRGGBB` strings for the theme file.
    var themeColors: Theme.Colors {
        Theme.Colors(background: background.hexString, surface: surface.hexString,
                     text: text.hexString, secondaryText: secondaryText.hexString,
                     accent: accent.hexString, textOnAccent: textOnAccent.hexString)
    }
}

// MARK: - Checks and automatic correction

/// The contrast rules of docs/05-temas.md, "Validación al importar", point 4.
enum ContrastCheck: String, CaseIterable, Sendable {
    case accentOnBackground
    case textOnAccentOnAccent
    case textOnBackground
    case textOnSurface
    case secondaryTextOnBackground

    /// 3:1 for the accent (large shapes and icons), 4,5:1 for text.
    var minimumRatio: Double {
        self == .accentOnBackground ? 3 : 4.5
    }
}

/// Which way a color is moved to reach the minimum contrast.
enum ContrastAdjustment: Sendable {
    case lighten
    case darken
}

/// A rule the theme does not meet, with the ratio it had and how it gets fixed.
struct ContrastIssue: Equatable, Sendable {
    var check: ContrastCheck
    var ratio: Double
    var adjustment: ContrastAdjustment
}

enum ThemeContrast {
    /// Size of each correction step: how much of white (or black) is mixed in per step.
    /// Small, so the corrected color stays as close as possible to the original.
    static let stepAmount = 0.02

    /// Fixes every rule the colors break and lists what was fixed.
    ///
    /// The foreground color of each pair is the one that moves (the background stays, it is
    /// the identity of the theme). Order matters because some colors are both: the accent is
    /// fixed against the background first, and then the text on the accent against the fixed
    /// accent.
    static func corrected(_ colors: ThemeColorSet) -> (colors: ThemeColorSet, issues: [ContrastIssue]) {
        var result = colors
        var issues: [ContrastIssue] = []

        // Accent on background (3:1).
        if let fix = fix(result.accent, against: [result.background],
                         minimum: ContrastCheck.accentOnBackground.minimumRatio) {
            issues.append(ContrastIssue(check: .accentOnBackground,
                                        ratio: result.accent.contrastRatio(with: result.background),
                                        adjustment: fix.adjustment))
            result.accent = fix.color
        }

        // Text on accent (4,5:1), against the accent as it ends up.
        if let fix = fix(result.textOnAccent, against: [result.accent],
                         minimum: ContrastCheck.textOnAccentOnAccent.minimumRatio) {
            issues.append(ContrastIssue(check: .textOnAccentOnAccent,
                                        ratio: result.textOnAccent.contrastRatio(with: result.accent),
                                        adjustment: fix.adjustment))
            result.textOnAccent = fix.color
        }

        // Text on background and on surface (4,5:1 both): one correction that satisfies both,
        // reported once per rule that failed.
        if let fix = fix(result.text, against: [result.background, result.surface],
                         minimum: ContrastCheck.textOnBackground.minimumRatio) {
            for (check, background) in [(ContrastCheck.textOnBackground, result.background),
                                        (.textOnSurface, result.surface)] {
                let ratio = result.text.contrastRatio(with: background)
                if ratio < check.minimumRatio {
                    issues.append(ContrastIssue(check: check, ratio: ratio,
                                                adjustment: fix.adjustment))
                }
            }
            result.text = fix.color
        }

        // Secondary text on background (4,5:1).
        if let fix = fix(result.secondaryText, against: [result.background],
                         minimum: ContrastCheck.secondaryTextOnBackground.minimumRatio) {
            issues.append(ContrastIssue(check: .secondaryTextOnBackground,
                                        ratio: result.secondaryText.contrastRatio(with: result.background),
                                        adjustment: fix.adjustment))
            result.secondaryText = fix.color
        }

        return (result, issues)
    }

    /// Returns `nil` when `color` already meets `minimum` against every background. Otherwise
    /// mixes it with white or black in small steps until it does.
    ///
    /// The direction is the one whose end point (pure white or pure black) has more contrast
    /// with the worst background. Against a single background, one of the two always reaches
    /// 4,5:1 (the worst case is ~4,6:1), so the loop always finds a color. With two very
    /// different backgrounds it may not; then the end point is returned, which is the best
    /// possible.
    static func fix(_ color: RGBColor, against backgrounds: [RGBColor],
                    minimum: Double) -> (color: RGBColor, adjustment: ContrastAdjustment)? {
        func worstRatio(_ candidate: RGBColor) -> Double {
            backgrounds.map { candidate.contrastRatio(with: $0) }.min() ?? 21
        }
        guard worstRatio(color) < minimum else { return nil }

        let adjustment: ContrastAdjustment = worstRatio(.white) >= worstRatio(.black) ? .lighten : .darken
        let target: RGBColor = adjustment == .lighten ? .white : .black
        var amount = stepAmount
        while amount < 1 {
            let candidate = color.mixed(with: target, amount: amount)
            if worstRatio(candidate) >= minimum {
                return (candidate, adjustment)
            }
            amount += stepAmount
        }
        return (target, adjustment)
    }

    /// "4,3:1". Rounded **down** to one decimal, so a failing 4,46 never shows as "4,5:1".
    /// Uses the app's UI language for the decimal separator, not the device region: a Spanish
    /// UI on a device set to a US region still shows "4,3:1", and an English UI "4.3:1".
    static func formattedRatio(_ ratio: Double, locale: Locale = .appLanguage) -> String {
        let truncated = (ratio * 10).rounded(.down) / 10
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let number = formatter.string(from: NSNumber(value: truncated)) ?? String(truncated)
        return number + ":1"
    }
}

extension Locale {
    /// The locale of the language the UI is shown in (the first localization of the bundle
    /// that matches the user's preferences: Spanish or English).
    static var appLanguage: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "es")
    }
}
