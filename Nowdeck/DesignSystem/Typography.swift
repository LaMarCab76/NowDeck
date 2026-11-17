import SwiftUI
import UIKit

/// A text style from docs/02-diseno.md: always the system font (Spotify guidelines), with
/// the size, weight, line height and tracking of the mockups.
///
/// Usage: `Text("…").textStyle(.trackTitle)`.
struct TextStyle: Equatable, Sendable {
    enum Design: Equatable, Sendable {
        case standard
        case monospaced
    }

    var size: CGFloat
    var weight: Font.Weight
    var design: Design = .standard
    /// Line height in points, as in the mockups' CSS `line-height`. `nil` = font default.
    var lineHeight: CGFloat?
    /// Letter spacing in em (CSS `letter-spacing`), converted to points on use.
    var trackingEm: CGFloat = 0
    /// Whether the size follows Dynamic Type. The player has a fixed layout and does not
    /// scale; onboarding and Settings do.
    var scalesWithDynamicType: Bool
    /// The Dynamic Type curve to follow when scaling.
    var relativeTo: Font.TextStyle = .body
}

extension TextStyle {
    // MARK: Player (fixed layout)

    static let trackTitle = TextStyle(size: 40, weight: .bold, lineHeight: 46, trackingEm: -0.02,
                                      scalesWithDynamicType: false)
    static let artist = TextStyle(size: 22, weight: .regular, lineHeight: 28,
                                  scalesWithDynamicType: false)
    static let playbackTime = TextStyle(size: 12, weight: .regular, design: .monospaced,
                                        scalesWithDynamicType: false)
    static let currentStanza = TextStyle(size: 30, weight: .bold, lineHeight: 38, trackingEm: -0.01,
                                         scalesWithDynamicType: false)
    static let nextStanza = TextStyle(size: 22, weight: .semibold, lineHeight: 30,
                                      scalesWithDynamicType: false)

    // MARK: Screens and sheets

    static let screenTitle = TextStyle(size: 34, weight: .bold, scalesWithDynamicType: true,
                                       relativeTo: .largeTitle)
    static let sheetTitle = TextStyle(size: 24, weight: .bold, scalesWithDynamicType: true,
                                      relativeTo: .title2)
    static let tab = TextStyle(size: 17, weight: .bold, scalesWithDynamicType: true,
                               relativeTo: .headline)
    static let body = TextStyle(size: 16, weight: .regular, lineHeight: 24,
                                scalesWithDynamicType: true)
    static let callout = TextStyle(size: 15, weight: .regular, scalesWithDynamicType: true,
                                   relativeTo: .callout)
    static let helper = TextStyle(size: 14, weight: .regular, lineHeight: 20,
                                  scalesWithDynamicType: true, relativeTo: .subheadline)
    static let footnote = TextStyle(size: 12, weight: .regular, lineHeight: 18,
                                    scalesWithDynamicType: true, relativeTo: .footnote)

    // MARK: Onboarding

    /// "Nowdeck" next to the logo.
    static let brandName = TextStyle(size: 22, weight: .bold, lineHeight: 28, trackingEm: -0.01,
                                     scalesWithDynamicType: true, relativeTo: .title2)
    /// "Tu iPhone, ahora control de escritorio."
    static let welcomeTitle = TextStyle(size: 34, weight: .bold, lineHeight: 38, trackingEm: -0.02,
                                        scalesWithDynamicType: true, relativeTo: .largeTitle)
    /// Titles of the two steps.
    static let stepTitle = TextStyle(size: 30, weight: .bold, lineHeight: 34, trackingEm: -0.02,
                                     scalesWithDynamicType: true, relativeTo: .title)
    /// Items of the check lists.
    static let listItem = TextStyle(size: 16, weight: .regular, lineHeight: 22,
                                    scalesWithDynamicType: true)
    static let stepNumber = TextStyle(size: 13, weight: .regular, design: .monospaced,
                                      scalesWithDynamicType: true, relativeTo: .footnote)
    /// The Redirect URI.
    static let code = TextStyle(size: 15, weight: .regular, design: .monospaced,
                                scalesWithDynamicType: true, relativeTo: .callout)
    /// The Client ID field.
    static let codeInput = TextStyle(size: 16, weight: .regular, design: .monospaced,
                                     scalesWithDynamicType: true)

    // MARK: Buttons

    static let primaryButton = TextStyle(size: 17, weight: .bold, scalesWithDynamicType: true,
                                         relativeTo: .headline)
    static let secondaryButton = TextStyle(size: 16, weight: .semibold,
                                           scalesWithDynamicType: true)
    static let backButton = TextStyle(size: 15, weight: .semibold, scalesWithDynamicType: true,
                                      relativeTo: .callout)
    static let smallButton = TextStyle(size: 14, weight: .semibold, scalesWithDynamicType: true,
                                       relativeTo: .subheadline)

    /// Uppercase monospaced labels ("VAS A NECESITAR").
    static let label = TextStyle(size: 12, weight: .regular, design: .monospaced, lineHeight: 16,
                                 trackingEm: 0.08, scalesWithDynamicType: true,
                                 relativeTo: .caption)
}

private struct TextStyleModifier: ViewModifier {
    let style: TextStyle
    @ScaledMetric private var scaledSize: CGFloat

    init(style: TextStyle) {
        self.style = style
        _scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        let size = style.scalesWithDynamicType ? scaledSize : style.size
        let scale = size / style.size
        return content
            .font(.system(size: size, weight: style.weight, design: fontDesign))
            .tracking(style.trackingEm * size)
            .lineSpacing(lineSpacing(size: size, scale: scale))
    }

    private var fontDesign: Font.Design {
        switch style.design {
        case .standard: return .default
        case .monospaced: return .monospaced
        }
    }

    /// SwiftUI has no line-height; it adds `lineSpacing` on top of the font's natural line
    /// height. When the design's line height is tighter than the font's, SwiftUI cannot
    /// reduce it, so we keep the natural one.
    private func lineSpacing(size: CGFloat, scale: CGFloat) -> CGFloat {
        guard let lineHeight = style.lineHeight else { return 0 }
        let uiFont: UIFont
        switch style.design {
        case .standard:
            uiFont = .systemFont(ofSize: size, weight: style.weight.uiFontWeight)
        case .monospaced:
            uiFont = .monospacedSystemFont(ofSize: size, weight: style.weight.uiFontWeight)
        }
        return max(0, lineHeight * scale - uiFont.lineHeight)
    }
}

extension View {
    func textStyle(_ style: TextStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}

private extension Font.Weight {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
