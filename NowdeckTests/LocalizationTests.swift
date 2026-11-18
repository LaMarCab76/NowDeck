import XCTest
@testable import Nowdeck

/// The UI is in Spanish (source language) and English. These tests read the String Catalogs
/// from the repository, so a UI string added without its English translation fails here
/// instead of showing up in Spanish on an English iPhone.
final class LocalizationTests: XCTestCase {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct StringUnit: Decodable {
                    var state: String
                    var value: String
                }
                var stringUnit: StringUnit?
            }
            var localizations: [String: Localization]?
        }
        var sourceLanguage: String
        var strings: [String: Entry]
    }

    private static var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Nowdeck/Resources")
    }

    private func catalog(_ name: String) throws -> Catalog {
        let data = try Data(contentsOf: Self.resources.appendingPathComponent(name))
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    /// `%@`, `%lld`, `%1$@`…: what has to match between a key and its translation, or the
    /// arguments end up in the wrong place (or crash the formatter).
    private func formatSpecifiers(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|d|@|f|%)"#)
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).map {
            // Positional and plain forms count as the same argument type.
            let raw = (text as NSString).substring(with: $0.range)
            return raw.replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression)
        }.sorted()
    }

    func testEveryStringHasAnEnglishTranslation() throws {
        for file in ["Localizable.xcstrings", "InfoPlist.xcstrings"] {
            let catalog = try catalog(file)
            XCTAssertEqual(catalog.sourceLanguage, "es", file)
            for (key, entry) in catalog.strings {
                let unit = entry.localizations?["en"]?.stringUnit
                XCTAssertEqual(unit?.state, "translated", "\(file): «\(key)» has no English")
                XCTAssertFalse(unit?.value.isEmpty ?? true, "\(file): «\(key)» is empty in English")
            }
        }
    }

    func testTranslationsKeepTheFormatArguments() throws {
        for file in ["Localizable.xcstrings", "InfoPlist.xcstrings"] {
            for (key, entry) in try catalog(file).strings {
                guard let value = entry.localizations?["en"]?.stringUnit?.value else { continue }
                XCTAssertEqual(formatSpecifiers(in: value), formatSpecifiers(in: key),
                               "\(file): «\(key)» → «\(value)»")
            }
        }
    }

    func testTheAppShipsAnEnglishTable() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(english.localizedString(forKey: "Volumen: %lld de 100", value: nil,
                                               table: nil),
                       "Volume: %lld of 100")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String],
                       ["es", "en"])
    }
}
