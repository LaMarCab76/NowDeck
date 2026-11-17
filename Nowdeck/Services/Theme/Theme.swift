import Foundation
import CoreGraphics

/// A Nowdeck theme, format `nowdeck.tema/1` (see docs/05-temas.md and
/// schemas/nowdeck.tema.v1.schema.json).
///
/// The JSON keys are in Spanish because they are part of the public file format; the Swift
/// names are in English. Everything except `format` and `name` is optional: missing values
/// fall back to the default theme when the theme is applied.
///
/// This type is plain data. Colors stay as raw strings here; they are parsed and validated
/// by `ThemeValidator` (files, clipboard, saved themes) and when building a `Palette`.
struct Theme: Codable, Equatable, Sendable {
    static let currentFormat = "nowdeck.tema/1"

    var format: String
    var name: String
    var colors: Colors?
    var playerBackground: PlayerBackground?
    /// How blurred the artist's photo is (`fondoReproductor: "artista"`), 0 to 100. Missing
    /// means 0; it is not filled in by the merge, so themes that never touched it (the
    /// presets) do not grow the field.
    var backgroundBlur: Int?
    var player: Player?
    var lyrics: Lyrics?

    enum CodingKeys: String, CodingKey {
        case format = "formato"
        case name = "nombre"
        case colors = "colores"
        case playerBackground = "fondoReproductor"
        case backgroundBlur = "desenfoqueFondo"
        case player = "reproductor"
        case lyrics = "letras"
    }

    struct Colors: Codable, Equatable, Sendable {
        var background: String?
        var surface: String?
        var text: String?
        var secondaryText: String?
        var accent: String?
        var textOnAccent: String?

        enum CodingKeys: String, CodingKey {
            case background = "fondo"
            case surface = "superficie"
            case text = "texto"
            case secondaryText = "textoSecundario"
            case accent = "acento"
            case textOnAccent = "textoSobreAcento"
        }
    }

    enum PlayerBackground: String, Codable, Sendable {
        /// Uses `colors.background`.
        case solid = "solido"
        /// Uses a soft color taken from the artwork.
        case artwork = "caratula"
        /// The artist's photo over the artwork color (owner's request, 2026-11-17).
        case artistPhoto = "artista"

        /// `caratula` and `artista` both start from the artwork color.
        var usesArtworkColor: Bool { self != .solid }
    }

    /// `desenfoqueFondo`: 0 (sharp) to 100.
    static let backgroundBlurRange = 0...100

    struct Player: Codable, Equatable, Sendable {
        var artworkPosition: ArtworkPosition?
        var controls: [PlayerControl]?

        enum CodingKeys: String, CodingKey {
            case artworkPosition = "caratula"
            case controls = "controles"
        }
    }

    enum ArtworkPosition: String, Codable, Sendable {
        case left = "izquierda"
        /// In the format but not designed yet: ignored with a warning on import.
        case right = "derecha"
    }

    enum PlayerControl: String, Codable, Sendable, CaseIterable {
        case shuffle = "aleatorio"
        case repeatMode = "repetir"
        case lyrics = "letras"
        case volume = "volumen"
    }

    struct Lyrics: Codable, Equatable, Sendable {
        var width: LyricsWidth?

        enum CodingKeys: String, CodingKey {
            case width = "ancho"
        }
    }

    enum LyricsWidth: String, Codable, Sendable {
        case half = "mitad"
        case twoThirds = "dos-tercios"
        case full = "completo"
    }
}

extension Theme {
    /// "Negro y verde", identical to themes/negro-y-verde.nowdeck.json.
    static let `default` = Theme(
        format: currentFormat,
        name: "Negro y verde",
        colors: Colors(
            background: "#000000",
            surface: "#161616",
            text: "#F2EEE8",
            secondaryText: "#A9B4C0",
            accent: "#2FD566",
            textOnAccent: "#00170A"
        ),
        playerBackground: .artwork,
        player: Player(
            artworkPosition: .left,
            controls: [.shuffle, .repeatMode, .lyrics, .volume]
        ),
        lyrics: Lyrics(width: .twoThirds)
    )
}

extension Theme {
    /// The theme with every missing field taken from the default theme (docs/05: "Al aplicar,
    /// se mezcla con el tema por defecto"). An explicit empty `controles` list is kept: it is
    /// a valid choice (no optional controls), not a missing value.
    func mergedWithDefault() -> Theme {
        let base = Theme.default
        let baseColors = base.colors!
        return Theme(
            format: Theme.currentFormat,
            name: name,
            colors: Colors(
                background: colors?.background ?? baseColors.background,
                surface: colors?.surface ?? baseColors.surface,
                text: colors?.text ?? baseColors.text,
                secondaryText: colors?.secondaryText ?? baseColors.secondaryText,
                accent: colors?.accent ?? baseColors.accent,
                textOnAccent: colors?.textOnAccent ?? baseColors.textOnAccent
            ),
            playerBackground: playerBackground ?? base.playerBackground,
            backgroundBlur: backgroundBlur,
            player: Player(
                artworkPosition: player?.artworkPosition ?? base.player?.artworkPosition,
                controls: player?.controls ?? base.player?.controls
            ),
            lyrics: Lyrics(width: lyrics?.width ?? base.lyrics?.width)
        )
    }
}

extension Theme.LyricsWidth {
    /// Share of the usable width taken by the lyrics (docs/02: 50 %, 66,7 % or 100 %).
    var fraction: CGFloat {
        switch self {
        case .half: return 0.5
        case .twoThirds: return 2.0 / 3.0
        case .full: return 1
        }
    }
}
