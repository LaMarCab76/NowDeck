import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Nowdeck

final class ThemeFileTests: XCTestCase {
    // MARK: Export

    func testFileNameIsASlugOfTheName() {
        func name(_ value: String) -> String {
            ThemeFile.fileName(for: Theme(format: Theme.currentFormat, name: value))
        }
        XCTAssertEqual(name("Negro y verde"), "negro-y-verde.nowdeck.json")
        XCTAssertEqual(name("Ámbar"), "ambar.nowdeck.json")
        XCTAssertEqual(name("  Azul   noche!! "), "azul-noche.nowdeck.json")
        XCTAssertEqual(name("Año 2026 / Ñandú"), "ano-2026-nandu.nowdeck.json")
        XCTAssertEqual(name("../../etc"), "etc.nowdeck.json")
        XCTAssertEqual(name("🌅"), "tema.nowdeck.json")
    }

    func testExportIsReadableUTF8WithSortedKeys() throws {
        let preset = try XCTUnwrap(ThemePresets.load().first { $0.id == "ambar" })
        let text = String(decoding: try ThemeFile.encode(preset.theme), as: UTF8.self)
        XCTAssertTrue(text.contains("\"Ámbar\""), "Not escaped as \\u00c1")
        XCTAssertTrue(text.contains("\n  \""), "Indented")
        // Sorted keys: colores < fondoReproductor < formato < letras < nombre < reproductor.
        let keys = ["\"colores\"", "\"fondoReproductor\"", "\"formato\"", "\"letras\"",
                    "\"nombre\"", "\"reproductor\""]
        let positions = try keys.map { try XCTUnwrap(text.range(of: $0)?.lowerBound) }
        XCTAssertEqual(positions, positions.sorted())
    }

    func testExportThenImportGivesTheSameTheme() throws {
        var custom = Theme.default
        custom.name = "Mío"
        custom.colors?.accent = "#C9A2FF"
        custom.playerBackground = .solid
        custom.player?.controls = [.volume, .shuffle]
        custom.lyrics?.width = .full

        for theme in ThemePresets.load().map(\.theme) + [custom] {
            let data = try ThemeFile.encode(theme)
            guard case .success(let validated) = ThemeValidator.validate(data) else {
                return XCTFail("\(theme.name) should import")
            }
            XCTAssertEqual(validated.warnings, [], theme.name)
            XCTAssertEqual(validated.themeToApply, theme, theme.name)
        }
    }

    @MainActor
    func testShareLinkFileHasTheThemeNameAndContents() throws {
        let store = ThemeStore()
        let url = try ThemeFile.writeTemporaryFile(for: store.export.theme)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(url.lastPathComponent, "negro-y-verde.nowdeck.json")
        XCTAssertEqual(try Data(contentsOf: url), try ThemeFile.encode(Theme.default))
    }

    func testExportedTypeConformsToJSON() {
        XCTAssertTrue(UTType.nowdeckTheme.conforms(to: .json))
        XCTAssertTrue(UTType.nowdeckTheme.identifier.hasSuffix(".theme"))
    }

    // MARK: Import from file

    func testReadingAHugeFileStopsAfterTheLimit() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("enorme-\(UUID().uuidString).nowdeck.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: UInt8(ascii: " "), count: 1_000_000).write(to: url)

        let data = try ThemeFile.readForImport(from: url)
        XCTAssertEqual(data.count, ThemeValidator.maximumSize + 1)
        XCTAssertEqual(try? ThemeValidator.validate(data).get(), nil)
        if case .failure(let error) = ThemeValidator.validate(data) {
            XCTAssertEqual(error, .tooLarge)
        }
    }
}

@MainActor
final class ThemeImportCoordinatorTests: XCTestCase {
    func testOAuthCallbackIsIgnored() {
        let coordinator = ThemeImportCoordinator()
        coordinator.handleOpenURL(URL(string: "nowdeck://callback?code=abc&state=xyz")!)
        coordinator.handleOpenURL(URL(string: "https://example.com/tema.nowdeck.json")!)
        XCTAssertNil(coordinator.request)
    }

    func testOpeningAThemeFileShowsTheImportSheet() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ambar-\(UUID().uuidString).nowdeck.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let preset = try XCTUnwrap(ThemePresets.load().first { $0.id == "ambar" })
        try ThemeFile.encode(preset.theme).write(to: url)

        let coordinator = ThemeImportCoordinator()
        coordinator.handleOpenURL(url)
        let request = try XCTUnwrap(coordinator.request)
        XCTAssertEqual(request.sourceName, url.lastPathComponent)
        XCTAssertTrue(request.contents.contains("\"Ámbar\""))
        XCTAssertEqual(try request.result.get().theme, preset.theme)

        coordinator.dismiss()
        XCTAssertNil(coordinator.request)
    }

    func testMissingFileIsReportedAsUnreadable() {
        let coordinator = ThemeImportCoordinator()
        coordinator.importFile(at: URL(fileURLWithPath: "/no/existe.nowdeck.json"))
        XCTAssertEqual(coordinator.request?.result, .failure(.unreadable))
    }

    func testClipboardImport() throws {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let coordinator = ThemeImportCoordinator()

        coordinator.importFromClipboard(pasteboard)
        XCTAssertEqual(coordinator.request?.result, .failure(.emptyClipboard))

        pasteboard.string = String(decoding: try ThemeFile.encode(Theme.default), as: UTF8.self)
        coordinator.importFromClipboard(pasteboard)
        XCTAssertEqual(try coordinator.request?.result.get().theme, Theme.default)

        pasteboard.string = "hola"
        coordinator.importFromClipboard(pasteboard)
        XCTAssertEqual(coordinator.request?.result, .failure(.invalidJSON))
    }

    func testDisplayedContentsAreCappedAt16KB() {
        let text = ThemeImportCoordinator.displayText(for: Data(repeating: 0x41, count: 100_000))
        XCTAssertEqual(text.utf8.count, ThemeValidator.maximumSize)
    }

    func testTopMostPresenterShowsTheSheet() {
        let coordinator = ThemeImportCoordinator()
        let root = UUID()
        let settings = UUID()
        coordinator.register(root)
        coordinator.register(settings)
        XCTAssertEqual(coordinator.activePresenter, settings)
        coordinator.unregister(settings)
        XCTAssertEqual(coordinator.activePresenter, root)
        coordinator.unregister(root)
        XCTAssertNil(coordinator.activePresenter)
    }
}
