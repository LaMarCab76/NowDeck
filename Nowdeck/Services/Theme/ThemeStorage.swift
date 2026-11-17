import Foundation

/// Saves themes as JSON files in Application Support (docs/05, "Modelo en Swift").
///
/// Two files:
/// - `active.nowdeck.json`: the theme in use, including the Reproductor options.
/// - `custom.nowdeck.json`: the last theme that was not a preset (imported or edited), so
///   the "Personalizado" chip can bring it back after trying a preset.
///
/// Themes are not secrets, so they do not go to the Keychain. Files are read back through
/// `ThemeValidator`, like any other theme file: a damaged file falls back to the default.
struct ThemeStorage: Sendable {
    enum Slot: String, Sendable {
        case active
        case custom
    }

    let directory: URL

    /// `Application Support/Theme/`.
    static func applicationSupport() -> ThemeStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ThemeStorage(directory: base.appendingPathComponent("Theme", isDirectory: true))
    }

    func url(for slot: Slot) -> URL {
        directory.appendingPathComponent("\(slot.rawValue).\(ThemeFile.fileExtension)")
    }

    func load(_ slot: Slot) -> Theme? {
        guard let data = try? ThemeFile.readForImport(from: url(for: slot)),
              case .success(let validated) = ThemeValidator.validate(data)
        else { return nil }
        return validated.themeToApply
    }

    /// Saving is best effort: if it fails, the theme still applies until the app quits, and
    /// there is nothing useful to tell the user.
    func save(_ theme: Theme?, to slot: Slot) {
        let url = url(for: slot)
        guard let theme else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ThemeFile.encode(theme).write(to: url, options: .atomic)
        } catch {
            // See above.
        }
    }
}
