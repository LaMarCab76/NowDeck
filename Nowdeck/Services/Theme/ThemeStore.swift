import SwiftUI

/// The four options of Ajustes → Apariencia → FONDO DEL REPRODUCTOR and how they map to the
/// theme (docs/05, "Correspondencia con Ajustes").
enum PlayerBackgroundOption: CaseIterable, Sendable {
    /// `fondoReproductor: "solido"` with `fondo: #000000`.
    case black
    /// `fondoReproductor: "solido"` with `fondo: #121212`.
    case darkGray
    /// `fondoReproductor: "caratula"`. The default.
    case artwork
    /// `fondoReproductor: "artista"`: the artist's photo over the artwork color.
    case artistPhoto

    static let blackHex = "#000000"
    static let darkGrayHex = "#121212"
}

/// Publishes the active theme, its palette and the player options to the view tree, and
/// keeps them saved.
///
/// Everything in Settings lives in the theme (docs/05): colors, player background, the
/// lyrics button ("Mostrar letras" = `letras` in `reproductor.controles`) and the lyrics
/// width. That way an exported theme carries the user's whole setup.
///
/// What the player and the lyrics view read (all published through `theme`):
/// `palette`, `playerBackground`, `playerControls`, `showsLyricsButton`, `lyricsWidth`.
@MainActor
final class ThemeStore: ObservableObject {
    /// Always complete: merged with the default theme and with contrast corrected.
    @Published private(set) var theme: Theme
    @Published private(set) var palette: Palette
    /// The last non-preset theme, restored by the "Personalizado" chip.
    @Published private(set) var customTheme: Theme?

    let presets: [ThemePreset]
    private let storage: ThemeStorage?

    /// In memory only (previews, tests).
    init(theme: Theme = .default, presets: [ThemePreset] = ThemePresets.load()) {
        let prepared = ThemeValidator.prepareForApplying(theme).theme
        self.theme = prepared
        self.palette = Palette(theme: prepared)
        self.presets = presets
        self.storage = nil
    }

    /// Loads the saved themes and saves every change.
    init(storage: ThemeStorage, presets: [ThemePreset] = ThemePresets.load()) {
        let active = storage.load(.active) ?? ThemeValidator.prepareForApplying(.default).theme
        self.theme = active
        self.palette = Palette(theme: active)
        self.customTheme = storage.load(.custom)
        self.presets = presets
        self.storage = storage
    }

    // MARK: Player options

    var playerBackground: Theme.PlayerBackground {
        theme.playerBackground ?? .artwork
    }

    /// "Desenfoque" of the artist's photo, 0 to 100.
    var backgroundBlur: Int {
        theme.backgroundBlur ?? Theme.defaultBackgroundBlur
    }

    /// "Oscurecer" of the artist's photo, 0 to 100.
    var backgroundDim: Int {
        theme.backgroundDim ?? Theme.defaultBackgroundDim
    }

    /// The optional controls, in the theme's order.
    var playerControls: [Theme.PlayerControl] {
        theme.player?.controls ?? Theme.PlayerControl.allCases
    }

    /// "Mostrar letras".
    var showsLyricsButton: Bool {
        playerControls.contains(.lyrics)
    }

    /// "Ancho de las letras". Use `lyricsWidth.fraction` for the layout.
    var lyricsWidth: Theme.LyricsWidth {
        theme.lyrics?.width ?? .twoThirds
    }

    // MARK: Settings state

    /// The preset with exactly the active colors, or `nil` for "Personalizado".
    var selectedPreset: ThemePreset? {
        let colors = ThemeColorSet(theme.colors)
        return presets.first { ThemeColorSet($0.theme.colors) == colors }
    }

    var accent: RGBColor { palette.accent }

    /// `nil` when the background is solid with a color that is neither black nor dark gray
    /// (for example the "Ámbar" preset): then no option is highlighted.
    var backgroundOption: PlayerBackgroundOption? {
        switch playerBackground {
        case .artwork: return .artwork
        case .artistPhoto: return .artistPhoto
        case .solid: break
        }
        switch palette.background.hexString {
        case PlayerBackgroundOption.blackHex: return .black
        case PlayerBackgroundOption.darkGrayHex: return .darkGray
        default: return nil
        }
    }

    // MARK: Settings actions

    /// Takes the preset's colors, player background and name. The Reproductor options
    /// (lyrics button, lyrics width) stay as the user set them.
    func selectPreset(_ preset: ThemePreset) {
        var next = theme
        next.name = preset.theme.name
        next.colors = preset.theme.colors
        next.playerBackground = preset.theme.playerBackground
        next.backgroundBlur = preset.theme.backgroundBlur
        next.backgroundDim = preset.theme.backgroundDim
        commit(next)
    }

    /// Brings back the last custom theme, keeping the Reproductor options. Does nothing if
    /// there is none yet.
    func selectCustom() {
        guard let customTheme, selectedPreset != nil else { return }
        var next = theme
        next.name = customTheme.name
        next.colors = customTheme.colors
        next.playerBackground = customTheme.playerBackground
        next.backgroundBlur = customTheme.backgroundBlur
        next.backgroundDim = customTheme.backgroundDim
        commit(next)
    }

    func setAccent(_ color: RGBColor) {
        var next = theme
        next.colors?.accent = color.hexString
        commitEdit(next)
    }

    func setBackgroundOption(_ option: PlayerBackgroundOption) {
        var next = theme
        switch option {
        case .black:
            next.playerBackground = .solid
            next.colors?.background = PlayerBackgroundOption.blackHex
        case .darkGray:
            next.playerBackground = .solid
            next.colors?.background = PlayerBackgroundOption.darkGrayHex
        case .artwork:
            next.playerBackground = .artwork
        case .artistPhoto:
            next.playerBackground = .artistPhoto
        }
        commitEdit(next)
    }

    func setBackgroundBlur(_ value: Int) {
        var next = theme
        next.backgroundBlur = value
        commitEdit(next)
    }

    func setBackgroundDim(_ value: Int) {
        var next = theme
        next.backgroundDim = value
        commitEdit(next)
    }

    func setShowsLyricsButton(_ isOn: Bool) {
        var controls = playerControls.filter { $0 != .lyrics }
        if isOn {
            // Put it back where it belongs in the standard order (before volume).
            let order = Theme.PlayerControl.allCases
            let index = controls.firstIndex {
                order.firstIndex(of: $0)! > order.firstIndex(of: .lyrics)!
            } ?? controls.endIndex
            controls.insert(.lyrics, at: index)
        }
        var next = theme
        next.player = Theme.Player(artworkPosition: .left, controls: controls)
        commitEdit(next)
    }

    func setLyricsWidth(_ width: Theme.LyricsWidth) {
        var next = theme
        next.lyrics = Theme.Lyrics(width: width)
        commitEdit(next)
    }

    /// "Aplicar tema" in the import sheet. The theme keeps its own name.
    func apply(_ validated: ValidatedTheme) {
        commit(validated.themeToApply)
    }

    /// The active theme as a file, for `ShareLink`.
    var export: ThemeExport {
        ThemeExport(theme: theme)
    }

    // MARK: Helpers

    /// An edit made in Settings. If it turns a preset into something else, the result is
    /// named "Personalizado" so that it is not exported with the preset's name.
    private func commitEdit(_ next: Theme) {
        var next = next
        if selectedPreset != nil {
            next.name = String(localized: "Personalizado")
        }
        commit(next)
    }

    private func commit(_ next: Theme) {
        var prepared = ThemeValidator.prepareForApplying(next).theme
        let colors = ThemeColorSet(prepared.colors)
        if let preset = presets.first(where: { ThemeColorSet($0.theme.colors) == colors }) {
            // Back to a preset's colors (for example, picking its accent again): use its name.
            prepared.name = preset.theme.name
        } else {
            customTheme = prepared
            storage?.save(prepared, to: .custom)
        }
        theme = prepared
        palette = Palette(theme: prepared)
        storage?.save(prepared, to: .active)
    }
}
