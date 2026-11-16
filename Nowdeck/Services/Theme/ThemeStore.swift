import SwiftUI

/// Publishes the active theme and its resolved palette to the view tree.
///
/// Milestone 0 only holds the default theme in memory. Persistence in Application Support,
/// presets, import and export arrive in milestone 7.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: Theme
    @Published private(set) var palette: Palette

    init(theme: Theme = .default) {
        self.theme = theme
        self.palette = Palette(theme: theme)
    }
}
