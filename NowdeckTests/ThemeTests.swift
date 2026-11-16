import XCTest
@testable import Nowdeck

final class ThemeTests: XCTestCase {
    /// The example themes in the repository's `themes/` folder. Read from the source tree
    /// (the simulator can read the host file system), so the tests always use the same
    /// files the docs and README point to.
    private var themesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NowdeckTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("themes")
    }

    private func loadTheme(_ fileName: String) throws -> Theme {
        let data = try Data(contentsOf: themesDirectory.appendingPathComponent(fileName))
        return try JSONDecoder().decode(Theme.self, from: data)
    }

    /// Listed explicitly: listing the directory from the simulator was very slow (~40 s) when
    /// the repository lives on an external volume.
    private let exampleThemeFiles = [
        "negro-y-verde.nowdeck.json",
        "ambar.nowdeck.json",
        "azul-noche.nowdeck.json",
        "atardecer.nowdeck.json",
    ]

    func testAllExampleThemesDecode() throws {
        for file in exampleThemeFiles {
            let theme = try loadTheme(file)
            XCTAssertEqual(theme.format, Theme.currentFormat, file)
            XCTAssertFalse(theme.name.isEmpty, file)
        }
    }

    func testDefaultThemeMatchesNegroYVerdeFile() throws {
        XCTAssertEqual(try loadTheme("negro-y-verde.nowdeck.json"), Theme.default)
    }

    func testMinimalThemeDecodesWithOptionalFieldsMissing() throws {
        let json = #"{"formato":"nowdeck.tema/1","nombre":"Mínimo"}"#
        let theme = try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        XCTAssertEqual(theme.name, "Mínimo")
        XCTAssertNil(theme.colors)
        XCTAssertNil(theme.playerBackground)
        XCTAssertNil(theme.player)
        XCTAssertNil(theme.lyrics)
    }

    func testEncodesWithSpanishKeys() throws {
        let data = try JSONEncoder().encode(Theme.default)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["formato"] as? String, "nowdeck.tema/1")
        XCTAssertEqual(object["fondoReproductor"] as? String, "caratula")
        let colors = try XCTUnwrap(object["colores"] as? [String: Any])
        XCTAssertEqual(colors["textoSobreAcento"] as? String, "#00170A")
    }
}
