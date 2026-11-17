import SwiftUI

// Tokens of the Settings and Import theme screens (Ajustes.dc.html, TemaImportar.dc.html).
// Kept in their own file, as extensions, so the shared design-system files stay untouched.

extension TextStyle {
    // MARK: Settings

    /// Vertical tabs "Apariencia" / "Reproductor".
    static let settingsTab = TextStyle(size: 16, weight: .semibold, scalesWithDynamicType: true)
    /// Theme chips, segmented options, outlined buttons, "Volver" and "Cancelar".
    static let pill = TextStyle(size: 15, weight: .semibold, scalesWithDynamicType: true,
                                relativeTo: .callout)
    /// "Mostrar letras".
    static let settingsRowTitle = TextStyle(size: 18, weight: .semibold, lineHeight: 24,
                                            scalesWithDynamicType: true, relativeTo: .headline)
    /// "Ancho de las letras".
    static let settingsOptionTitle = TextStyle(size: 16, weight: .semibold, lineHeight: 22,
                                               scalesWithDynamicType: true)
    /// The LRCLIB note.
    static let settingsNote = TextStyle(size: 14, weight: .regular, lineHeight: 21,
                                        scalesWithDynamicType: true, relativeTo: .subheadline)

    // MARK: Import theme

    /// "Importar tema" (sheet title with the mockup's tracking).
    static let importTitle = TextStyle(size: 24, weight: .bold, lineHeight: 30, trackingEm: -0.01,
                                       scalesWithDynamicType: true, relativeTo: .title2)
    /// File name next to the title.
    static let importFileName = TextStyle(size: 12, weight: .regular, design: .monospaced,
                                          scalesWithDynamicType: true, relativeTo: .caption)
    /// The JSON of the file.
    static let importCode = TextStyle(size: 12, weight: .regular, design: .monospaced,
                                      lineHeight: 17, scalesWithDynamicType: true,
                                      relativeTo: .caption)
    /// "Tema válido" or the error title.
    static let importStatus = TextStyle(size: 16, weight: .bold, lineHeight: 22,
                                        scalesWithDynamicType: true)
    /// Name in the preview card.
    static let importPreviewTitle = TextStyle(size: 15, weight: .bold, lineHeight: 20,
                                              scalesWithDynamicType: true, relativeTo: .callout)
    /// "Vista previa".
    static let importPreviewSubtitle = TextStyle(size: 13, weight: .regular, lineHeight: 18,
                                                 scalesWithDynamicType: true, relativeTo: .footnote)
    /// Warnings and error details.
    static let importMessage = TextStyle(size: 13, weight: .regular, lineHeight: 19,
                                         scalesWithDynamicType: true, relativeTo: .footnote)
    /// "Aplicar tema".
    static let importApply = TextStyle(size: 16, weight: .bold, scalesWithDynamicType: true)
}

extension Palette {
    // MARK: Settings (translucent whites of the mockup)

    /// Selected vertical tab.
    static let settingsTabSelected = Color.white.opacity(0.12)
    /// Selected theme chip fill.
    static let chipSelectedFill = Color.white.opacity(0.08)
    /// Unselected theme chip border.
    static let chipUnselectedBorder = Color.white.opacity(0.25)
    /// Ring around the accent sample of a theme chip.
    static let chipSwatchRing = Color.white.opacity(0.3)
    /// Container of the segmented controls.
    static let segmentTrack = Color.white.opacity(0.08)
    /// Card of "Mostrar letras".
    static let settingsCard = Color.white.opacity(0.07)
    /// Switch track when off.
    static let switchTrackOff = Color.white.opacity(0.22)
    /// "Exportar tema" / "Importar tema" border.
    static let settingsButtonBorder = Color.white.opacity(0.4)

    // MARK: Import theme

    /// Background of the JSON box.
    static let codeBackground = RGBColor(hex: "#0A0A0A")!
    /// Border of the JSON box.
    static let codeBorder = RGBColor(hex: "#2A2A2A")!
    /// Sheet handle.
    static let sheetHandle = Color.white.opacity(0.35)
    /// Round close button.
    static let closeButtonFill = Color.white.opacity(0.1)
}

/// The accent colors of Ajustes → COLOR DE RESALTADO (docs/02), in the mockup's order.
struct AccentChoice: Identifiable, Sendable {
    let name: LocalizedStringResource
    let color: RGBColor
    var id: String { color.hexString }

    static let all: [AccentChoice] = [
        AccentChoice(name: "Verde", color: RGBColor(hex: "#2FD566")!),
        AccentChoice(name: "Ámbar", color: RGBColor(hex: "#FFB23E")!),
        AccentChoice(name: "Celeste", color: RGBColor(hex: "#7CC4FF")!),
        AccentChoice(name: "Coral", color: RGBColor(hex: "#FF7A7A")!),
        AccentChoice(name: "Lavanda", color: RGBColor(hex: "#C9A2FF")!),
        AccentChoice(name: "Blanco", color: RGBColor(hex: "#F2EEE8")!),
    ]
}

/// Margins of a landscape screen: the mockup's value, or the safe area when it is larger
/// (the notch or Dynamic Island of newer iPhones is deeper than 48 pt).
struct SettingsMargins {
    var top: CGFloat
    var horizontal: CGFloat
    var bottom: CGFloat

    func insets(for safeArea: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: max(top, safeArea.top),
                   leading: max(horizontal, safeArea.leading),
                   bottom: max(bottom, safeArea.bottom),
                   trailing: max(horizontal, safeArea.trailing))
    }
}
