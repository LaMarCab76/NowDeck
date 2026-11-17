import XCTest
@testable import Nowdeck

@MainActor
final class ThemeStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemeStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var storage: ThemeStorage { ThemeStorage(directory: directory) }

    private func preset(_ id: String, in store: ThemeStore) throws -> ThemePreset {
        try XCTUnwrap(store.presets.first { $0.id == id })
    }

    // MARK: Presets

    func testBundledPresetsAreTheThreeOfTheMockupInOrder() throws {
        let presets = ThemePresets.load()
        XCTAssertEqual(presets.map(\.id), ["negro-y-verde", "ambar", "azul-noche"])
        XCTAssertEqual(presets.map(\.theme.name), ["Negro y verde", "Ámbar", "Azul noche"])
        XCTAssertEqual(presets.first?.theme, Theme.default)
        XCTAssertFalse(presets.contains { $0.theme.name == "Atardecer" })
    }

    func testBundledPresetsMatchTheRepositoryFiles() throws {
        for preset in ThemePresets.load() {
            let url = ThemeValidatorTests.repositoryThemes.appendingPathComponent("\(preset.id).nowdeck.json")
            let theme = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url))
            XCTAssertEqual(preset.theme, theme, preset.id)
        }
    }

    // MARK: Defaults and player options

    func testFreshStoreUsesTheDefaultTheme() {
        let store = ThemeStore(storage: storage)
        XCTAssertEqual(store.theme, Theme.default)
        XCTAssertEqual(store.palette, Palette.default)
        XCTAssertEqual(store.selectedPreset?.id, "negro-y-verde")
        XCTAssertEqual(store.playerBackground, .artwork)
        XCTAssertEqual(store.backgroundOption, .artwork)
        XCTAssertTrue(store.showsLyricsButton)
        XCTAssertEqual(store.playerControls, [.shuffle, .repeatMode, .lyrics, .volume])
        XCTAssertEqual(store.lyricsWidth, .twoThirds)
        XCTAssertEqual(store.lyricsWidth.fraction, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertNil(store.customTheme)
    }

    func testLyricsSwitchRemovesAndRestoresTheButtonInPlace() {
        let store = ThemeStore(storage: storage)
        store.setShowsLyricsButton(false)
        XCTAssertFalse(store.showsLyricsButton)
        XCTAssertEqual(store.playerControls, [.shuffle, .repeatMode, .volume])
        store.setShowsLyricsButton(true)
        XCTAssertEqual(store.playerControls, [.shuffle, .repeatMode, .lyrics, .volume])
        // Player options do not make the theme custom.
        XCTAssertEqual(store.selectedPreset?.id, "negro-y-verde")
        XCTAssertEqual(store.theme.name, "Negro y verde")
    }

    func testLyricsWidth() {
        let store = ThemeStore(storage: storage)
        store.setLyricsWidth(.full)
        XCTAssertEqual(store.lyricsWidth, .full)
        XCTAssertEqual(store.lyricsWidth.fraction, 1)
        store.setLyricsWidth(.half)
        XCTAssertEqual(store.lyricsWidth.fraction, 0.5)
    }

    // MARK: Appearance

    func testPlayerBackgroundOptionsMapToTheThemeAsInDocs() {
        let store = ThemeStore(storage: storage)

        store.setBackgroundOption(.darkGray)
        XCTAssertEqual(store.theme.playerBackground, .solid)
        XCTAssertEqual(store.theme.colors?.background, "#121212")
        XCTAssertEqual(store.backgroundOption, .darkGray)

        store.setBackgroundOption(.black)
        XCTAssertEqual(store.theme.playerBackground, .solid)
        XCTAssertEqual(store.theme.colors?.background, "#000000")
        XCTAssertEqual(store.backgroundOption, .black)

        store.setBackgroundOption(.artwork)
        XCTAssertEqual(store.theme.playerBackground, .artwork)
        XCTAssertEqual(store.backgroundOption, .artwork)
    }

    func testSolidThemeBackgroundHighlightsNoOption() throws {
        let store = ThemeStore(storage: storage)
        store.selectPreset(try preset("ambar", in: store))
        // Ámbar is solid on #121A24: neither "Negro" nor "Gris oscuro".
        XCTAssertNil(store.backgroundOption)
        XCTAssertEqual(store.playerBackground, .solid)
    }

    func testSelectingAPresetKeepsThePlayerOptions() throws {
        let store = ThemeStore(storage: storage)
        store.setShowsLyricsButton(false)
        store.setLyricsWidth(.full)
        store.selectPreset(try preset("azul-noche", in: store))
        XCTAssertEqual(store.theme.name, "Azul noche")
        XCTAssertEqual(store.palette.accent.hexString, "#7CC4FF")
        XCTAssertEqual(store.playerBackground, .solid)
        XCTAssertFalse(store.showsLyricsButton)
        XCTAssertEqual(store.lyricsWidth, .full)
        XCTAssertEqual(store.selectedPreset?.id, "azul-noche")
    }

    func testEditingAPresetMakesItCustomAndPersonalizadoBringsItBack() throws {
        let store = ThemeStore(storage: storage)
        store.selectPreset(try preset("ambar", in: store))
        store.setAccent(try XCTUnwrap(RGBColor(hex: "#FF7A7A")))

        XCTAssertNil(store.selectedPreset)
        XCTAssertEqual(store.theme.name, "Personalizado")
        XCTAssertEqual(store.theme.colors?.accent, "#FF7A7A")
        XCTAssertEqual(store.theme.colors?.background, "#121A24")
        XCTAssertEqual(store.customTheme, store.theme)

        let custom = store.theme
        store.selectPreset(try preset("negro-y-verde", in: store))
        XCTAssertEqual(store.selectedPreset?.id, "negro-y-verde")
        store.selectCustom()
        XCTAssertEqual(store.theme, custom)
    }

    func testPickingThePresetAccentAgainReturnsToThePreset() throws {
        let store = ThemeStore(storage: storage)
        store.setAccent(try XCTUnwrap(RGBColor(hex: "#C9A2FF")))
        XCTAssertNil(store.selectedPreset)
        store.setAccent(try XCTUnwrap(RGBColor(hex: "#2FD566")))
        XCTAssertEqual(store.selectedPreset?.id, "negro-y-verde")
        XCTAssertEqual(store.theme.name, "Negro y verde")
    }

    func testPersonalizadoDoesNothingBeforeThereIsACustomTheme() {
        let store = ThemeStore(storage: storage)
        store.selectCustom()
        XCTAssertEqual(store.theme, Theme.default)
    }

    // MARK: Import

    func testApplyingAnImportedThemeUsesTheCorrectedColorsAndItsName() throws {
        let data = try Data(contentsOf: ThemeValidatorTests.repositoryThemes
            .appendingPathComponent("atardecer.nowdeck.json"))
        guard case .success(let validated) = ThemeValidator.validate(data) else {
            return XCTFail("Atardecer should be valid")
        }
        let store = ThemeStore(storage: storage)
        store.apply(validated)
        XCTAssertEqual(store.theme.name, "Atardecer")
        XCTAssertNil(store.selectedPreset)
        XCTAssertEqual(store.customTheme, store.theme)
        XCTAssertNotEqual(store.theme.colors?.secondaryText, "#8A6F7A")
        XCTAssertGreaterThanOrEqual(
            store.palette.tertiaryText.contrastRatio(with: store.palette.background), 4.5
        )
    }

    // MARK: Persistence

    func testEverySettingSurvivesARestart() throws {
        let store = ThemeStore(storage: storage)
        store.selectPreset(try preset("azul-noche", in: store))
        store.setAccent(try XCTUnwrap(RGBColor(hex: "#FFB23E")))
        store.setBackgroundOption(.darkGray)
        store.setShowsLyricsButton(false)
        store.setLyricsWidth(.half)

        let restarted = ThemeStore(storage: storage)
        XCTAssertEqual(restarted.theme, store.theme)
        XCTAssertEqual(restarted.palette, store.palette)
        XCTAssertEqual(restarted.customTheme, store.customTheme)
        XCTAssertEqual(restarted.palette.accent.hexString, "#FFB23E")
        XCTAssertEqual(restarted.backgroundOption, .darkGray)
        XCTAssertFalse(restarted.showsLyricsButton)
        XCTAssertEqual(restarted.lyricsWidth, .half)
    }

    func testThemeIsSavedAsAThemeFileInTheStorageDirectory() throws {
        let store = ThemeStore(storage: storage)
        store.setLyricsWidth(.full)
        let data = try Data(contentsOf: storage.url(for: .active))
        guard case .success(let validated) = ThemeValidator.validate(data) else {
            return XCTFail("The saved file should be a valid theme")
        }
        XCTAssertEqual(validated.theme.lyrics?.width, .full)
    }

    func testDamagedSavedThemeFallsBackToTheDefault() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ roto".utf8).write(to: storage.url(for: .active))
        XCTAssertEqual(ThemeStore(storage: storage).theme, Theme.default)
    }

    func testInMemoryStoreDoesNotWriteFiles() {
        let store = ThemeStore()
        store.setLyricsWidth(.half)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
