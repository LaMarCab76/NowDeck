import Foundation

/// A built-in theme, shown as a chip in Settings → Apariencia → TEMA.
struct ThemePreset: Identifiable, Equatable, Sendable {
    /// The file's base name, e.g. "ambar".
    let id: String
    let theme: Theme
}

enum ThemePresets {
    /// In the order of the mockup (Ajustes.dc.html). The files are copied from `themes/` into
    /// the app bundle (project.yml).
    ///
    /// `atardecer.nowdeck.json` is deliberately **not** a preset: its secondary text has
    /// 4,3:1 against its background, below the 4,5:1 the app promises (docs/05), and the
    /// product doc and the mockup list only these three. It stays in `themes/` as the import
    /// example of the mockup (TemaImportar.dc.html), where that warning is shown.
    static let fileNames = ["negro-y-verde", "ambar", "azul-noche"]

    /// Loads and validates the bundled presets. A preset that is missing or invalid is
    /// skipped (tests make sure none is); the default theme is always there.
    static func load(from bundle: Bundle = .main) -> [ThemePreset] {
        var presets: [ThemePreset] = []
        for name in fileNames {
            guard let url = bundle.url(forResource: name, withExtension: ThemeFile.fileExtension),
                  let data = try? Data(contentsOf: url),
                  case .success(let validated) = ThemeValidator.validate(data)
            else { continue }
            presets.append(ThemePreset(id: name, theme: validated.themeToApply))
        }
        if !presets.contains(where: { $0.theme.colors == Theme.default.colors }) {
            presets.insert(ThemePreset(id: fileNames[0], theme: .default), at: 0)
        }
        return presets
    }
}
