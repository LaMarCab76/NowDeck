import Foundation

/// Why a theme cannot be imported (docs/05-temas.md, "Validación al importar").
enum ThemeImportError: Error, Equatable, Sendable {
    /// More than `ThemeValidator.maximumSize` bytes.
    case tooLarge
    /// The file could not be read (permissions, file gone).
    case unreadable
    /// Paste was chosen but the clipboard has no text.
    case emptyClipboard
    /// Not JSON, or JSON whose top level is not an object.
    case invalidJSON
    /// `formato` is missing or is not a Nowdeck theme format.
    case notANowdeckTheme
    /// `formato` is `nowdeck.tema/N` with N greater than the supported version.
    case newerVersion
    /// `nombre` is missing, empty, longer than 40 characters or has control characters.
    case invalidName
    /// A color that is not `#RRGGBB`. The associated value is the field, e.g. "colores.acento".
    case invalidColor(field: String)
    /// A known field with the wrong type or a value outside the allowed list.
    case invalidValue(field: String)

    var message: LocalizedStringResource {
        switch self {
        case .tooLarge:
            return "El archivo pesa más de 16 KB. Un tema es mucho más chico: revisá que sea el archivo correcto."
        case .unreadable:
            return "No pudimos leer el archivo. Probá abrirlo de nuevo."
        case .emptyClipboard:
            return "El portapapeles no tiene texto. Copiá el contenido del tema y probá de nuevo."
        case .invalidJSON:
            return "No es un tema de Nowdeck: el texto no es un JSON válido."
        case .notANowdeckTheme:
            return "No es un tema de Nowdeck."
        case .newerVersion:
            return "Este tema es de una versión más nueva de Nowdeck."
        case .invalidName:
            return "El nombre del tema tiene que tener entre 1 y 40 caracteres."
        case .invalidColor(let field):
            return "El color de «\(field)» no es válido: tiene que tener la forma #RRGGBB."
        case .invalidValue(let field):
            return "El valor de «\(field)» no es válido."
        }
    }
}

/// Something the user should know before applying, that does not block the import.
enum ThemeImportWarning: Equatable, Sendable {
    /// Fields this version does not know. They are ignored (forward compatibility).
    case unknownFields([String])
    /// `reproductor.caratula: "derecha"` has no design yet: the artwork stays on the left.
    case artworkOnRightNotSupported
    /// A contrast rule that fails. The color is corrected when the theme is applied.
    case lowContrast(ContrastIssue)

    var message: LocalizedStringResource {
        switch self {
        case .unknownFields(let fields):
            let list = ThemeValidator.displayList(fields)
            return "Hay campos que esta versión no conoce y se van a ignorar: \(list)."
        case .artworkOnRightNotSupported:
            return "La carátula a la derecha todavía no está disponible: se va a mostrar a la izquierda."
        case .lowContrast(let issue):
            let ratio = ThemeContrast.formattedRatio(issue.ratio)
            switch (issue.check, issue.adjustment) {
            case (.accentOnBackground, .lighten):
                return "El color de resaltado tiene poco contraste con el fondo (\(ratio)). Lo vamos a aclarar al aplicarlo."
            case (.accentOnBackground, .darken):
                return "El color de resaltado tiene poco contraste con el fondo (\(ratio)). Lo vamos a oscurecer al aplicarlo."
            case (.textOnAccentOnAccent, .lighten):
                return "El texto sobre el color de resaltado tiene poco contraste (\(ratio)). Lo vamos a aclarar al aplicarlo."
            case (.textOnAccentOnAccent, .darken):
                return "El texto sobre el color de resaltado tiene poco contraste (\(ratio)). Lo vamos a oscurecer al aplicarlo."
            case (.textOnBackground, .lighten):
                return "El texto tiene poco contraste con el fondo (\(ratio)). Lo vamos a aclarar al aplicarlo."
            case (.textOnBackground, .darken):
                return "El texto tiene poco contraste con el fondo (\(ratio)). Lo vamos a oscurecer al aplicarlo."
            case (.textOnSurface, .lighten):
                return "El texto tiene poco contraste con la superficie (\(ratio)). Lo vamos a aclarar al aplicarlo."
            case (.textOnSurface, .darken):
                return "El texto tiene poco contraste con la superficie (\(ratio)). Lo vamos a oscurecer al aplicarlo."
            case (.secondaryTextOnBackground, .lighten):
                return "El texto secundario tiene poco contraste con el fondo (\(ratio)). Lo vamos a aclarar al aplicarlo."
            case (.secondaryTextOnBackground, .darken):
                return "El texto secundario tiene poco contraste con el fondo (\(ratio)). Lo vamos a oscurecer al aplicarlo."
            }
        }
    }
}

/// A theme that passed validation.
struct ValidatedTheme: Equatable, Sendable {
    /// The theme as written in the file (trimmed name, no defaults filled in). Used for the
    /// preview, which shows the theme's own colors.
    var theme: Theme
    var warnings: [ThemeImportWarning]
    /// What "Aplicar" stores: merged with the default theme, artwork forced to the left and
    /// colors corrected for contrast.
    var themeToApply: Theme
}

/// Validates untrusted theme data (a file, AirDrop, the clipboard).
///
/// Security (AGENTS.md, docs/05 "Seguridad"): a theme is **data only**. This code reads a
/// bounded amount of JSON, picks the known fields one by one with strict types, and builds a
/// `Theme` from them. Nothing in the file is executed, loaded or used as a URL, path or
/// format string; unknown fields are dropped (only their names are shown, shortened).
enum ThemeValidator {
    /// docs/05: 16 KB. Larger input is rejected before parsing.
    static let maximumSize = 16 * 1024
    /// docs/05 / schema: `nombre` has 1 to 40 characters.
    static let maximumNameLength = 40

    private static let formatPrefix = "nowdeck.tema/"
    private static let supportedVersion = 1

    private static let topLevelFields: Set<String> = [
        "formato", "nombre", "colores", "fondoReproductor", "reproductor", "letras",
    ]
    private static let colorFields = ["fondo", "superficie", "texto", "textoSecundario",
                                      "acento", "textoSobreAcento"]
    private static let playerFields: Set<String> = ["caratula", "controles"]
    private static let lyricsFields: Set<String> = ["ancho"]

    static func validate(_ data: Data) -> Result<ValidatedTheme, ThemeImportError> {
        // 1. Size.
        guard data.count <= maximumSize else { return .failure(.tooLarge) }

        // 2. JSON and format.
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let root = object as? [String: Any]
        else { return .failure(.invalidJSON) }

        switch formatStatus(root["formato"]) {
        case .supported: break
        case .newer: return .failure(.newerVersion)
        case .other: return .failure(.notANowdeckTheme)
        }

        guard let name = validName(root["nombre"]) else { return .failure(.invalidName) }

        var unknownFields = root.keys.filter { !topLevelFields.contains($0) }
        var theme = Theme(format: Theme.currentFormat, name: name)

        // 3. Colors.
        if let value = root["colores"] {
            guard let colors = value as? [String: Any] else {
                return .failure(.invalidValue(field: "colores"))
            }
            var parsed: [String: String] = [:]
            for field in colorFields {
                guard let raw = colors[field] else { continue }
                guard let hex = raw as? String, isStrictHexColor(hex) else {
                    return .failure(.invalidColor(field: "colores.\(field)"))
                }
                parsed[field] = hex.uppercased()
            }
            unknownFields += colors.keys.filter { !colorFields.contains($0) }.map { "colores.\($0)" }
            theme.colors = Theme.Colors(
                background: parsed["fondo"], surface: parsed["superficie"],
                text: parsed["texto"], secondaryText: parsed["textoSecundario"],
                accent: parsed["acento"], textOnAccent: parsed["textoSobreAcento"]
            )
        }

        // Player options (schema enums).
        if let value = root["fondoReproductor"] {
            guard let background = (value as? String).flatMap(Theme.PlayerBackground.init(rawValue:)) else {
                return .failure(.invalidValue(field: "fondoReproductor"))
            }
            theme.playerBackground = background
        }

        if let value = root["reproductor"] {
            guard let player = value as? [String: Any] else {
                return .failure(.invalidValue(field: "reproductor"))
            }
            var parsed = Theme.Player()
            if let raw = player["caratula"] {
                guard let position = (raw as? String).flatMap(Theme.ArtworkPosition.init(rawValue:)) else {
                    return .failure(.invalidValue(field: "reproductor.caratula"))
                }
                parsed.artworkPosition = position
            }
            if let raw = player["controles"] {
                guard let controls = validControls(raw) else {
                    return .failure(.invalidValue(field: "reproductor.controles"))
                }
                parsed.controls = controls
            }
            unknownFields += player.keys.filter { !playerFields.contains($0) }.map { "reproductor.\($0)" }
            theme.player = parsed
        }

        if let value = root["letras"] {
            guard let lyrics = value as? [String: Any] else {
                return .failure(.invalidValue(field: "letras"))
            }
            var parsed = Theme.Lyrics()
            if let raw = lyrics["ancho"] {
                guard let width = (raw as? String).flatMap(Theme.LyricsWidth.init(rawValue:)) else {
                    return .failure(.invalidValue(field: "letras.ancho"))
                }
                parsed.width = width
            }
            unknownFields += lyrics.keys.filter { !lyricsFields.contains($0) }.map { "letras.\($0)" }
            theme.lyrics = parsed
        }

        // Warnings.
        var warnings: [ThemeImportWarning] = []
        if !unknownFields.isEmpty {
            warnings.append(.unknownFields(unknownFields.sorted()))
        }
        if theme.player?.artworkPosition == .right {
            warnings.append(.artworkOnRightNotSupported)
        }

        // 4. Contrast, on the colors that will actually be used (merged with the default).
        let (toApply, issues) = prepareForApplying(theme)
        warnings += issues.map(ThemeImportWarning.lowContrast)

        return .success(ValidatedTheme(theme: theme, warnings: warnings, themeToApply: toApply))
    }

    /// Merges with the default theme, drops what has no design yet (artwork on the right) and
    /// corrects contrast. Also used by `ThemeStore` for its own edits.
    static func prepareForApplying(_ theme: Theme) -> (theme: Theme, issues: [ContrastIssue]) {
        var merged = theme.mergedWithDefault()
        merged.player?.artworkPosition = .left
        // After the merge every color is present; validated colors are well formed. A theme
        // built in code with a malformed color falls back to the default colors.
        let colors = ThemeColorSet(merged.colors) ?? ThemeColorSet(Theme.default.colors)!
        let (corrected, issues) = ThemeContrast.corrected(colors)
        merged.colors = corrected.themeColors
        return (merged, issues)
    }

    // MARK: Field rules

    private enum FormatStatus {
        case supported
        case newer
        case other
    }

    private static func formatStatus(_ value: Any?) -> FormatStatus {
        guard let format = value as? String else { return .other }
        if format == Theme.currentFormat { return .supported }
        guard format.hasPrefix(formatPrefix),
              let version = Int(format.dropFirst(formatPrefix.count)),
              version > supportedVersion
        else { return .other }
        return .newer
    }

    /// Trimmed name, or `nil` if it breaks the rules. Control characters (line breaks, tabs,
    /// escapes) are rejected: the name is shown in one line in the UI and in the file name.
    private static func validName(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...maximumNameLength).contains(name.count),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return name
    }

    /// `^#[0-9A-Fa-f]{6}$`, ASCII only.
    static func isStrictHexColor(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 7, bytes[0] == UInt8(ascii: "#") else { return false }
        return bytes.dropFirst().allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
        }
    }

    /// An ordered subset of the four controls, without repeats (schema: `uniqueItems`).
    private static func validControls(_ value: Any) -> [Theme.PlayerControl]? {
        guard let items = value as? [Any], items.count <= Theme.PlayerControl.allCases.count else {
            return nil
        }
        var controls: [Theme.PlayerControl] = []
        for item in items {
            guard let control = (item as? String).flatMap(Theme.PlayerControl.init(rawValue:)),
                  !controls.contains(control)
            else { return nil }
            controls.append(control)
        }
        return controls
    }

    // MARK: Display helpers

    /// Unknown field names come from the file: show at most five, each shortened and without
    /// control characters, so a hostile file cannot flood the sheet.
    static func displayList(_ fields: [String]) -> String {
        let shown = fields.prefix(5).map { field -> String in
            let clean = String(String.UnicodeScalarView(
                field.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            ))
            return clean.count > 30 ? String(clean.prefix(29)) + "…" : clean
        }
        let list = shown.joined(separator: ", ")
        let hidden = fields.count - shown.count
        return hidden > 0 ? "\(list) (+\(hidden))" : list
    }
}
