import SwiftUI

// Measurements, colors and text styles of the library, search and mini player
// (`Biblioteca.dc.html`). Kept in their own file, as extensions of the shared design system.

extension Metrics {
    enum Library {
        /// Screen padding: 28 top, 48 sides, 10 bottom. Blocks are spread with
        /// `space-between`.
        static let top: CGFloat = 28
        static let horizontal: CGFloat = 48
        static let bottom: CGFloat = 10

        // Row 1: tabs and logo.
        static let rowHeight: CGFloat = 44
        static let rowGap: CGFloat = 16
        static let tabTrackPadding: CGFloat = 4
        /// The track is moved 4 pt left so the active tab lines up with the filters.
        static let tabTrackOffset: CGFloat = -4
        static let tabHeight: CGFloat = 36
        static let tabHorizontalPadding: CGFloat = 18
        /// "Buscar" has a magnifier: 14 pt on its left side instead of 18.
        static let searchTabLeadingPadding: CGFloat = 14
        static let tabIconSize: CGFloat = 18
        static let tabIconGap: CGFloat = 8

        // Row 2: filters and "ABRIR SPOTIFY".
        static let filterHeight: CGFloat = 36
        static let filterHorizontalPadding: CGFloat = 16
        static let filterBorderWidth: CGFloat = 1.5
        static let filterGap: CGFloat = 8
        static let openSpotifyIconSize: CGFloat = 14
        static let openSpotifyIconGap: CGFloat = 6

        // Cards.
        static let cardSize: CGFloat = 150
        static let cardGap: CGFloat = 20
        static let cardTextGap: CGFloat = 10
        /// Name (22) + subtitle (18) line heights.
        static let cardTextHeight: CGFloat = 40
        static var rowHeightWithText: CGFloat { cardSize + cardTextGap + cardTextHeight }
        /// The "more in Spotify" card that ends each row is not artwork: card radius.
        static let moreCardRadius: CGFloat = 12
        static let moreCardIconSize: CGFloat = 28
        static let placeholderCount = 5

        // Search.
        static let searchBlockHeight: CGFloat = 248
        static let searchBlockGap: CGFloat = 18
        static let searchFieldHeight: CGFloat = 56
        static let searchFieldPadding: CGFloat = 18
        static let searchFieldIconSize: CGFloat = 22
        static let searchFieldIconGap: CGFloat = 12
        static let searchHelpMaxWidth: CGFloat = 520

        // Mini player.
        static let miniHeight: CGFloat = 56
        static let miniRadius: CGFloat = 14
        static let miniLeadingPadding: CGFloat = 8
        static let miniTrailingPadding: CGFloat = 6
        static let miniGap: CGFloat = 8
        static let miniArtworkSize: CGFloat = 40
        static let miniArtworkGap: CGFloat = 12
        static let miniTitleGap: CGFloat = 8
        static let miniDevicePadding: CGFloat = 10
        static let miniDeviceIconSize: CGFloat = 18
        static let miniDeviceIconGap: CGFloat = 8
        static let miniPlayButtonSize: CGFloat = 44
        static let miniPlayIconSize: CGFloat = 17
    }
}

extension Palette {
    /// Container of the Biblioteca / Buscar tabs (white at 8 %).
    static let libraryTabTrack = Color.white.opacity(0.08)
    /// The search field (white at 10 %).
    static let searchField = Color.white.opacity(0.1)
    /// Mini player background when the artwork gives no color.
    static let miniPlayerFallback = Color.white.opacity(0.09)
}

extension TextStyle {
    /// Card name: 16 pt semibold, line height 22.
    static let cardTitle = TextStyle(size: 16, weight: .semibold, lineHeight: 22,
                                     scalesWithDynamicType: false)
    /// Card subtitle: 13 pt, line height 18.
    static let cardSubtitle = TextStyle(size: 13, weight: .regular, lineHeight: 18,
                                        scalesWithDynamicType: false)
    /// Filter chips: 15 pt semibold.
    static let libraryFilter = TextStyle(size: 15, weight: .semibold,
                                         scalesWithDynamicType: false)
    /// Biblioteca / Buscar: 17 pt bold (the shared `tab` style without Dynamic Type, since
    /// the screen has a fixed layout).
    static let libraryTab = TextStyle(size: 17, weight: .bold, scalesWithDynamicType: false)
    /// Text typed in the search field: 18 pt.
    static let searchInput = TextStyle(size: 18, weight: .regular, scalesWithDynamicType: false)
    /// "Tocá un resultado…": 15 pt, line height 22.
    static let searchHelp = TextStyle(size: 15, weight: .regular, lineHeight: 22,
                                      scalesWithDynamicType: false)
    /// Mini player title (16 semibold) and artist (14).
    static let miniTitle = TextStyle(size: 16, weight: .semibold, scalesWithDynamicType: false)
    static let miniSubtitle = TextStyle(size: 14, weight: .regular, scalesWithDynamicType: false)
    /// "Suena en" (14 medium) and the device (14 bold).
    static let miniDevicePrefix = TextStyle(size: 14, weight: .medium, scalesWithDynamicType: false)
    static let miniDeviceName = TextStyle(size: 14, weight: .bold, scalesWithDynamicType: false)
}
