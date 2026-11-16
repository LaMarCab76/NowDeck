import Foundation

/// A Nowdeck theme, format `nowdeck.tema/1` (see docs/05-temas.md and
/// schemas/nowdeck.tema.v1.schema.json).
///
/// The JSON keys are in Spanish because they are part of the public file format; the Swift
/// names are in English. Everything except `format` and `name` is optional: missing values
/// fall back to the default theme when the theme is applied.
///
/// This type is plain data. Colors stay as raw strings here; they are parsed and validated
/// when building a `Palette` (and, in milestone 7, by the import validator).
struct Theme: Codable, Equatable, Sendable {
    static let currentFormat = "nowdeck.tema/1"

    var format: String
    var name: String
    var colors: Colors?
    var playerBackground: PlayerBackground?
    var player: Player?
    var lyrics: Lyrics?

    enum CodingKeys: String, CodingKey {
        case format = "formato"
        case name = "nombre"
        case colors = "colores"
        case playerBackground = "fondoReproductor"
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
    }

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
