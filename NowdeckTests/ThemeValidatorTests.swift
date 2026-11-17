import XCTest
@testable import Nowdeck

/// Every case of docs/05-temas.md, "Validación al importar", plus the schema rules.
final class ThemeValidatorTests: XCTestCase {
    // MARK: Helpers

    private let validJSON = #"""
    {
      "formato": "nowdeck.tema/1",
      "nombre": "Prueba",
      "colores": {
        "fondo": "#000000",
        "superficie": "#161616",
        "texto": "#F2EEE8",
        "textoSecundario": "#A9B4C0",
        "acento": "#2FD566",
        "textoSobreAcento": "#00170A"
      },
      "fondoReproductor": "solido",
      "reproductor": { "caratula": "izquierda", "controles": ["volumen", "aleatorio"] },
      "letras": { "ancho": "mitad" }
    }
    """#

    /// Test JSON is written with single quotes (Swift raw strings clash with "#RRGGBB");
    /// they become double quotes here. No test value contains an apostrophe.
    private func validate(_ json: String) -> Result<ValidatedTheme, ThemeImportError> {
        ThemeValidator.validate(Data(json.replacingOccurrences(of: "'", with: "\"").utf8))
    }

    private func validated(_ json: String, file: StaticString = #filePath,
                           line: UInt = #line) throws -> ValidatedTheme {
        switch validate(json) {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("Expected a valid theme, got \(error)", file: file, line: line)
            throw error
        }
    }

    private func assertError(_ json: String, _ expected: ThemeImportError,
                             file: StaticString = #filePath, line: UInt = #line) {
        switch validate(json) {
        case .success: XCTFail("Expected \(expected), got a valid theme", file: file, line: line)
        case .failure(let error): XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    /// A minimal theme with one extra top-level member (raw JSON).
    private func minimal(_ extra: String = "") -> String {
        let tail = extra.isEmpty ? "" : ", " + extra
        return "{'formato':'nowdeck.tema/1','nombre':'Mínimo'" + tail + "}"
    }

    // MARK: Valid input

    func testValidThemeIsReadFieldByField() throws {
        let result = try validated(validJSON)
        XCTAssertEqual(result.theme.name, "Prueba")
        XCTAssertEqual(result.theme.colors?.accent, "#2FD566")
        XCTAssertEqual(result.theme.playerBackground, .solid)
        XCTAssertEqual(result.theme.player?.controls, [.volume, .shuffle])
        XCTAssertEqual(result.theme.lyrics?.width, .half)
        XCTAssertEqual(result.warnings, [])
    }

    func testArtistBackgroundAndBlurAreRead() throws {
        let result = try validated(minimal("'fondoReproductor':'artista','desenfoqueFondo':40"))
        XCTAssertEqual(result.theme.playerBackground, .artistPhoto)
        XCTAssertEqual(result.theme.backgroundBlur, 40)
        XCTAssertEqual(result.warnings, [])
        XCTAssertNil(try validated(minimal()).themeToApply.backgroundBlur,
                     "Not added by the merge: missing means sharp")
    }

    func testBlurMustBeAWholeNumberFrom0To100() {
        for bad in ["true", "12.5", "101", "-1", "'40'", "null"] {
            assertError(minimal("'desenfoqueFondo':" + bad), .invalidValue(field: "desenfoqueFondo"))
        }
        XCTAssertNoThrow(try validated(minimal("'desenfoqueFondo':100")))
        XCTAssertNoThrow(try validated(minimal("'desenfoqueFondo':0")))
    }

    func testMissingFieldsAreFilledWithTheDefaultThemeWhenApplying() throws {
        let result = try validated(minimal("'colores':{'acento':'#7CC4FF'}"))
        XCTAssertNil(result.theme.playerBackground)
        let applied = result.themeToApply
        XCTAssertEqual(applied.name, "Mínimo")
        XCTAssertEqual(applied.colors?.accent, "#7CC4FF")
        XCTAssertEqual(applied.colors?.background, "#000000")
        XCTAssertEqual(applied.playerBackground, .artwork)
        XCTAssertEqual(applied.player?.controls, Theme.PlayerControl.allCases)
        XCTAssertEqual(applied.lyrics?.width, .twoThirds)
    }

    func testEmptyControlListIsKept() throws {
        let result = try validated(minimal("'reproductor':{'controles':[]}"))
        XCTAssertEqual(result.themeToApply.player?.controls, [])
    }

    func testLowercaseHexIsAcceptedAndStoredUppercase() throws {
        let result = try validated(minimal("'colores':{'acento':'#2fd566'}"))
        XCTAssertEqual(result.theme.colors?.accent, "#2FD566")
    }

    func testNameIsTrimmed() throws {
        XCTAssertEqual(try validated("{'formato':'nowdeck.tema/1','nombre':'  Azul  '}").theme.name, "Azul")
    }

    // MARK: 1. Size

    func testRejectsMoreThan16KB() {
        let padding = String(repeating: " ", count: ThemeValidator.maximumSize)
        assertError(minimal() + padding, .tooLarge)
    }

    func testAcceptsExactly16KB() throws {
        let base = minimal()
        let padded = base + String(repeating: " ", count: ThemeValidator.maximumSize - base.utf8.count)
        XCTAssertEqual(padded.utf8.count, 16 * 1024)
        _ = try validated(padded)
    }

    // MARK: 2. JSON and format

    func testRejectsInvalidJSON() {
        assertError("", .invalidJSON)
        assertError("no es json", .invalidJSON)
        assertError("{'formato': 'nowdeck.tema/1', 'nombre': 'Corto'", .invalidJSON)
        // Valid JSON but not an object.
        assertError("['nowdeck.tema/1']", .invalidJSON)
        assertError("'nowdeck.tema/1'", .invalidJSON)
    }

    func testMissingOrOtherFormatIsNotANowdeckTheme() {
        assertError("{'nombre':'Sin formato'}", .notANowdeckTheme)
        assertError("{'formato':'otra.app/1','nombre':'X'}", .notANowdeckTheme)
        assertError("{'formato':'nowdeck.tema/0','nombre':'X'}", .notANowdeckTheme)
        assertError("{'formato':'nowdeck.tema/','nombre':'X'}", .notANowdeckTheme)
        assertError("{'formato':'nowdeck.tema/1.0','nombre':'X'}", .notANowdeckTheme)
        assertError("{'formato':1,'nombre':'X'}", .notANowdeckTheme)
    }

    func testNewerFormatVersionIsReported() {
        assertError("{'formato':'nowdeck.tema/2','nombre':'Futuro'}", .newerVersion)
        assertError("{'formato':'nowdeck.tema/12','nombre':'Futuro'}", .newerVersion)
    }

    func testNewerVersionMessageMatchesDocs() {
        XCTAssertEqual(String(localized: ThemeImportError.newerVersion.message),
                       "Este tema es de una versión más nueva de Nowdeck.")
        XCTAssertEqual(String(localized: ThemeImportError.notANowdeckTheme.message),
                       "No es un tema de Nowdeck.")
    }

    func testNameRules() throws {
        assertError("{'formato':'nowdeck.tema/1'}", .invalidName)
        assertError("{'formato':'nowdeck.tema/1','nombre':''}", .invalidName)
        assertError("{'formato':'nowdeck.tema/1','nombre':'   '}", .invalidName)
        assertError("{'formato':'nowdeck.tema/1','nombre':42}", .invalidName)
        assertError("{'formato':'nowdeck.tema/1','nombre':'Dos\\nlíneas'}", .invalidName)
        assertError("{'formato':'nowdeck.tema/1','nombre':'\(String(repeating: "a", count: 41))'}",
                    .invalidName)
        // 40 characters (with accents, counted as characters, not bytes) is fine.
        let forty = String(repeating: "á", count: 40)
        XCTAssertEqual(try validated("{'formato':'nowdeck.tema/1','nombre':'\(forty)'}").theme.name, forty)
    }

    // MARK: 3. Colors

    func testEveryColorFieldMustBeHashPlusSixHexDigits() {
        let fields = ["fondo", "superficie", "texto", "textoSecundario", "acento", "textoSobreAcento"]
        let invalid = ["'#FFF'", "'2FD566'", "'#2FD5667'", "'#GGGGGG'", "'red'",
                       "'#２FD566'", "'rgb(0,0,0)'", "123", "null", "true", "['#000000']"]
        for field in fields {
            for value in invalid {
                assertError(minimal("'colores':{'\(field)':\(value)}"),
                            .invalidColor(field: "colores.\(field)"))
            }
        }
    }

    func testColorsMustBeAnObject() {
        assertError(minimal("'colores':'#000000'"), .invalidValue(field: "colores"))
        assertError(minimal("'colores':['#000000']"), .invalidValue(field: "colores"))
    }

    func testStrictHexMatcher() {
        XCTAssertTrue(ThemeValidator.isStrictHexColor("#A9b4C0"))
        XCTAssertFalse(ThemeValidator.isStrictHexColor("#A9B4C"))
        XCTAssertFalse(ThemeValidator.isStrictHexColor(" #A9B4C0"))
        XCTAssertFalse(ThemeValidator.isStrictHexColor("#A9B4C0\n"))
        XCTAssertFalse(ThemeValidator.isStrictHexColor("#A9B4C\u{FF10}"))
    }

    // MARK: Options (schema enums)

    func testOptionValuesMustBeInTheSchema() {
        assertError(minimal("'fondoReproductor':'degradado'"), .invalidValue(field: "fondoReproductor"))
        assertError(minimal("'fondoReproductor':true"), .invalidValue(field: "fondoReproductor"))
        assertError(minimal("'reproductor':'izquierda'"), .invalidValue(field: "reproductor"))
        assertError(minimal("'reproductor':{'caratula':'arriba'}"),
                    .invalidValue(field: "reproductor.caratula"))
        assertError(minimal("'letras':{'ancho':'doble'}"), .invalidValue(field: "letras.ancho"))
        assertError(minimal("'letras':'mitad'"), .invalidValue(field: "letras"))
    }

    func testControlsMustBeAnOrderedSubsetWithoutRepeats() {
        let field = ThemeImportError.invalidValue(field: "reproductor.controles")
        assertError(minimal("'reproductor':{'controles':'volumen'}"), field)
        assertError(minimal("'reproductor':{'controles':['volumen','volumen']}"), field)
        assertError(minimal("'reproductor':{'controles':['karaoke']}"), field)
        assertError(minimal("'reproductor':{'controles':[1]}"), field)
        assertError(minimal("'reproductor':{'controles':['aleatorio','repetir','letras','volumen','aleatorio']}"),
                    field)
    }

    // MARK: Warnings

    func testUnknownFieldsAreIgnoredAndReported() throws {
        let json = minimal("'script':'alert(1)','imagen':'https://example.com/x.png','colores':{'brillo':'#FFFFFF'},'reproductor':{'tamaño':3},'letras':{'fuente':'Comic'}")
        let result = try validated(json)
        XCTAssertEqual(result.warnings, [.unknownFields(["colores.brillo", "imagen", "letras.fuente",
                                                         "reproductor.tamaño", "script"])])
        // Nothing of the unknown fields reaches the theme: it is rebuilt from known fields.
        let encoded = String(decoding: try ThemeFile.encode(result.themeToApply), as: UTF8.self)
        XCTAssertFalse(encoded.contains("https"))
        XCTAssertFalse(encoded.contains("alert"))
        XCTAssertFalse(encoded.contains("Comic"))
    }

    func testUnknownFieldListIsShortenedForDisplay() {
        let fields = (1...8).map { "campo\($0)" } + [String(repeating: "x", count: 100) + "\u{0007}"]
        let list = ThemeValidator.displayList(fields)
        XCTAssertEqual(list, "campo1, campo2, campo3, campo4, campo5 (+4)")
        XCTAssertEqual(ThemeValidator.displayList([String(repeating: "x", count: 40) + "\u{0007}"]),
                       String(repeating: "x", count: 29) + "…")
    }

    func testArtworkOnTheRightIsIgnoredWithAWarning() throws {
        let result = try validated(minimal("'reproductor':{'caratula':'derecha'}"))
        XCTAssertEqual(result.theme.player?.artworkPosition, .right)
        XCTAssertEqual(result.warnings, [.artworkOnRightNotSupported])
        XCTAssertEqual(result.themeToApply.player?.artworkPosition, .left)
    }

    // MARK: 4. Contrast

    func testAtardecerHasTheLowSecondaryTextContrastOfTheMockup() throws {
        let data = try Data(contentsOf: Self.repositoryThemes.appendingPathComponent("atardecer.nowdeck.json"))
        guard case .success(let result) = ThemeValidator.validate(data) else {
            return XCTFail("Atardecer should be valid")
        }
        XCTAssertEqual(result.warnings.count, 1)
        guard case .lowContrast(let issue) = result.warnings.first else {
            return XCTFail("Expected a contrast warning")
        }
        XCTAssertEqual(issue.check, .secondaryTextOnBackground)
        XCTAssertEqual(issue.adjustment, .lighten)
        XCTAssertEqual(issue.ratio, 4.31, accuracy: 0.01)
        // The mockup's text (TemaImportar.dc.html).
        XCTAssertEqual(String(localized: ThemeImportWarning.lowContrast(issue).message),
                       "El texto secundario tiene poco contraste con el fondo (4,3:1). Lo vamos a aclarar al aplicarlo.")

        // Applying lightens it just enough, and keeps everything else.
        let original = try XCTUnwrap(RGBColor(hex: "#8A6F7A"))
        let background = try XCTUnwrap(RGBColor(hex: "#120A0F"))
        let fixed = try XCTUnwrap(RGBColor(hex: result.themeToApply.colors?.secondaryText ?? ""))
        XCTAssertGreaterThanOrEqual(fixed.contrastRatio(with: background), 4.5)
        XCTAssertLessThan(fixed.contrastRatio(with: background), 4.8)
        XCTAssertGreaterThan(fixed.relativeLuminance, original.relativeLuminance)
        XCTAssertEqual(result.themeToApply.colors?.accent, "#FF8A5B")
        XCTAssertEqual(result.themeToApply.colors?.text, "#FFF4EC")
    }

    func testEveryContrastRuleProducesAWarning() throws {
        // Dark text on a dark theme, dark accent, accent-colored text on the accent.
        let json = minimal(#"""
        "colores":{"fondo":"#101010","superficie":"#202020","texto":"#303030",
                   "textoSecundario":"#404040","acento":"#252525","textoSobreAcento":"#2A2A2A"}
        """#)
        let result = try validated(json)
        let checks = result.warnings.compactMap { warning -> ContrastCheck? in
            if case .lowContrast(let issue) = warning { return issue.check }
            return nil
        }
        XCTAssertEqual(Set(checks), Set(ContrastCheck.allCases))
        let colors = try XCTUnwrap(ThemeColorSet(result.themeToApply.colors))
        XCTAssertGreaterThanOrEqual(colors.accent.contrastRatio(with: colors.background), 3)
        XCTAssertGreaterThanOrEqual(colors.textOnAccent.contrastRatio(with: colors.accent), 4.5)
        XCTAssertGreaterThanOrEqual(colors.text.contrastRatio(with: colors.background), 4.5)
        XCTAssertGreaterThanOrEqual(colors.text.contrastRatio(with: colors.surface), 4.5)
        XCTAssertGreaterThanOrEqual(colors.secondaryText.contrastRatio(with: colors.background), 4.5)
    }

    func testContrastIsCheckedOnColorsMergedWithTheDefault() throws {
        // Only a white background: the default light text no longer has contrast.
        let result = try validated(minimal("'colores':{'fondo':'#FFFFFF','superficie':'#FFFFFF'}"))
        let checks = result.warnings.compactMap { warning -> ContrastIssue? in
            if case .lowContrast(let issue) = warning { return issue }
            return nil
        }
        XCTAssertTrue(checks.contains { $0.check == .textOnBackground && $0.adjustment == .darken })
    }

    // MARK: Example files

    static var repositoryThemes: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("themes")
    }

    func testPresetFilesAreValidWithoutWarnings() throws {
        for name in ThemePresets.fileNames {
            let data = try Data(contentsOf: Self.repositoryThemes.appendingPathComponent("\(name).nowdeck.json"))
            guard case .success(let result) = ThemeValidator.validate(data) else {
                return XCTFail("\(name) should be valid")
            }
            XCTAssertEqual(result.warnings, [], name)
            XCTAssertEqual(result.themeToApply, result.theme, "\(name) needs no defaults nor corrections")
        }
    }
}
