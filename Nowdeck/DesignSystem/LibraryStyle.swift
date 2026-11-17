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
        static let miniDevicePadding: CGFloat = 10
        static let miniDeviceIconSize: CGFloat = 18
        static let miniDeviceIconGap: CGFloat = 8
        static let miniPlayButtonSize: CGFloat = 44
        static let miniPlayIconSize: CGFloat = 17

        // Detail of a playlist or an album (`Detalle.dc.html`).
        /// "‹ Biblioteca": a 36 pt pill like an inactive tab, moved 4 pt left like the tabs.
        static let backHeight: CGFloat = 36
        static let backLeadingPadding: CGFloat = 10
        static let backTrailingPadding: CGFloat = 16
        static let backIconSize: CGFloat = 18
        static let backIconGap: CGFloat = 6
        /// Between "ABRIR EN SPOTIFY" and the logo.
        static let detailHeaderGap: CGFloat = 20
        static let detailHeight: CGFloat = 252
        static let detailColumnGap: CGFloat = 32
        static let detailInfoWidth: CGFloat = 170
        static let detailNameTopGap: CGFloat = 10
        static let detailPlayWidth: CGFloat = 150
        static let detailPlayHeight: CGFloat = 44
        static let detailPlayIconSize: CGFloat = 16
        static let detailPlayIconGap: CGFloat = 8
        static let trackListLabelHeight: CGFloat = 22
        static let trackRowHeight: CGFloat = 50
        static let trackNumberWidth: CGFloat = 22
        static let trackRowGap: CGFloat = 14
        static let trackTitleGap: CGFloat = 6
        static let trackExplicitSize: CGFloat = 15
        static let trackSeparatorWidth: CGFloat = 1
        static let trackUnavailableOpacity: Double = 0.4
        static let trackListFadeHeight: CGFloat = 36
        static let trackPlaceholderCount = 4
        /// Playlists of other people: icon, title, text and "Ver en Spotify".
        static let restrictedMaxWidth: CGFloat = 440
        static let restrictedIconSize: CGFloat = 28
        static let restrictedGap: CGFloat = 10
        static let outlineButtonHeight: CGFloat = 44
        static let outlineButtonPadding: CGFloat = 18
    }
}

extension Palette {
    /// Container of the Biblioteca / Buscar tabs (white at 8 %).
    static let libraryTabTrack = Color.white.opacity(0.08)
    /// The search field (white at 10 %).
    static let searchField = Color.white.opacity(0.1)
    /// Mini player background when the artwork gives no color.
    static let miniPlayerFallback = Color.white.opacity(0.09)
    /// Lines between the tracks of the detail screen (white at 10 %, like Dispositivos).
    static let trackSeparator = Color.white.opacity(0.1)
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

    // Detail of a playlist or an album.
    /// Name under the artwork: 18 pt bold, line height 22.
    static let detailName = TextStyle(size: 18, weight: .bold, lineHeight: 22,
                                      scalesWithDynamicType: false)
    /// "Reproducir": 16 pt bold.
    static let detailPlay = TextStyle(size: 16, weight: .bold, scalesWithDynamicType: false)
    /// "48 TEMAS · 2 H 51 MIN": 12 pt monospaced, tracking +0.08em.
    static let trackListLabel = TextStyle(size: 12, weight: .regular, design: .monospaced,
                                          trackingEm: 0.08, scalesWithDynamicType: false)
    /// Track title in the list: 16 pt semibold, line height 21.
    static let trackRowTitle = TextStyle(size: 16, weight: .semibold, lineHeight: 21,
                                         scalesWithDynamicType: false)
    /// Number and duration of a track: 12 pt monospaced.
    static let trackRowNumber = TextStyle(size: 12, weight: .regular, design: .monospaced,
                                          scalesWithDynamicType: false)
    /// "Spotify no muestra los temas…": 20 pt bold, line height 26.
    static let restrictedTitle = TextStyle(size: 20, weight: .bold, lineHeight: 26,
                                           scalesWithDynamicType: false)
}
