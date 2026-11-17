import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// `<bundle ID>.theme`, the exported type declared in project.yml for `.nowdeck.json`.
    /// Built from the bundle ID because forks change it (Config/Local.xcconfig).
    static var nowdeckTheme: UTType {
        UTType(exportedAs: (Bundle.main.bundleIdentifier ?? "com.lamarcab76.nowdeck") + ".theme",
               conformingTo: .json)
    }
}

/// Reading and writing `.nowdeck.json` files.
enum ThemeFile {
    static let fileExtension = "nowdeck.json"

    /// docs/05 "Exportar": UTF-8, readable (indented) and with sorted keys.
    static func encode(_ theme: Theme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(theme)
        data.append(contentsOf: Array("\n".utf8))
        return data
    }

    /// `<nombre-en-slug>.nowdeck.json`: lowercase ASCII letters and digits joined by "-".
    /// Accents are folded ("Ámbar" → "ambar"). Falls back to "tema" if nothing is left.
    static func fileName(for theme: Theme) -> String {
        let folded = theme.name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                        locale: Locale(identifier: "es"))
        var slug = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash, !slug.isEmpty { slug.append("-") }
                slug.unicodeScalars.append(scalar)
                pendingDash = false
            } else {
                pendingDash = true
            }
        }
        return (slug.isEmpty ? "tema" : slug.lowercased()) + "." + fileExtension
    }

    /// Writes the theme to a new temporary folder, so the shared file has the theme's name.
    static func writeTemporaryFile(for theme: Theme) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemeExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(for: theme))
        try encode(theme).write(to: url, options: .atomic)
        return url
    }

    /// Reads at most `ThemeValidator.maximumSize + 1` bytes: enough for the validator to tell
    /// that a file is too large without loading a huge file into memory.
    ///
    /// Files from the file picker or from other apps are security-scoped; access is always
    /// closed again (docs/05, "Seguridad").
    static func readForImport(from url: URL) throws -> Data {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: ThemeValidator.maximumSize + 1) ?? Data()
    }
}

/// The active theme as a shareable file, for `ShareLink`.
struct ThemeExport: Transferable {
    let theme: Theme

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .nowdeckTheme) { export in
            SentTransferredFile(try ThemeFile.writeTemporaryFile(for: export.theme))
        }
    }
}
