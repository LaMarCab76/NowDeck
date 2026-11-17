import CoreGraphics

/// The two lyrics options of Settings → Reproductor (docs/01-producto.md, `Ajustes.dc.html`).
///
/// A plain value so Settings (milestone 7) can store it however it stores the rest and hand
/// it to the player. The sync mode (word by word or whole stanza) is not a setting: it
/// depends on what LRCLIB has for each track (docs/04-letras.md).
struct LyricsSettings: Equatable, Codable, Sendable {
    /// "Mostrar letras". Off by default: the lyrics come from a community database, and the
    /// rights belong to the publishers (docs/04-letras.md, docs/06-cumplimiento.md).
    var isEnabled = false
    /// "Ancho de las letras". 2/3 by default.
    var width: LyricsWidth = .twoThirds
}

/// How much of the usable width the stanzas take.
enum LyricsWidth: String, CaseIterable, Codable, Sendable {
    /// "Mitad": 50 %.
    case half
    /// "2/3": 66.667 %.
    case twoThirds
    /// "Completo": 100 %.
    case full

    var fraction: CGFloat {
        switch self {
        case .half: return 0.5
        case .twoThirds: return 2.0 / 3.0
        case .full: return 1
        }
    }
}
