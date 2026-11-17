import SwiftUI

// Measurements, colors and text styles of the player (`Main.dc.html`) and "Nada sonando"
// (`SinReproduccion.dc.html`). Kept in their own file, as extensions of the shared design
// system, so that other screens' changes don't collide with these.

extension Metrics {
    /// Player screen (`Main.dc.html`). Margins are in `Spacing.Player`.
    enum Player {
        /// Height of the top block (artwork and text column).
        static let topBlockHeight: CGFloat = 256
        static let artworkSize: CGFloat = 256
        /// Between the artwork and the text column.
        static let artworkGap: CGFloat = 32
        /// Artwork side on narrow screens: `min(top block height, screen width × 0.3)`
        /// (docs/02-diseno.md, "Adaptación al iPhone 8 Plus").
        static let artworkWidthFraction: CGFloat = 0.3

        /// Row with the logo, origin, Biblioteca and Ajustes.
        static let topRowHeight: CGFloat = 44
        static let topRowGap: CGFloat = 12
        /// Spotify logo: 108×30 inside a 44 pt tap zone.
        static let logoSize = CGSize(width: 108, height: 30)
        /// Space between the logo and "Desde la playlist". The mockup has 10, but Spotify's
        /// guidelines ask for a clear space of half the logo height (15): see docs/06.
        static let logoClearSpace: CGFloat = 15
        static let topButtonsGap: CGFloat = 6
        static let libraryPillLeadingPadding: CGFloat = 12
        static let libraryPillTrailingPadding: CGFloat = 16
        static let libraryPillIconGap: CGFloat = 8
        static let libraryIconSize: CGFloat = 20
        static let settingsIconSize: CGFloat = 22

        static let titleArtistGap: CGFloat = 6
        static let titleLineLimit = 2

        static let deviceRowHeight: CGFloat = 44
        static let deviceIconGap: CGFloat = 10
        static let deviceIconSize: CGFloat = 20

        /// Bottom block: progress row and controls.
        static let bottomBlockGap: CGFloat = 14
        static let progressRowHeight: CGFloat = 16
        static let progressRowGap: CGFloat = 14
        static let progressTimeWidth: CGFloat = 36
        static let progressBarHeight: CGFloat = 4

        static let controlsHeight: CGFloat = 64
        /// Width of the side groups (shuffle/repeat and lyrics/volume).
        static let sideGroupWidth: CGFloat = 200
        /// …on screens narrower than `narrowScreenWidth` (iPhone 8 Plus: 736).
        static let narrowSideGroupWidth: CGFloat = 160
        static let narrowScreenWidth: CGFloat = 800
        static let sideButtonSize: CGFloat = 48
        static let sideButtonGap: CGFloat = 4
        static let sideIconSize: CGFloat = 22
        static let centerGap: CGFloat = 20
        static let skipButtonSize: CGFloat = 56
        static let skipIconSize: CGFloat = 28
        static let playButtonSize: CGFloat = 64
        static let playIconSize: CGFloat = 26
    }

    /// "Nada sonando" (`SinReproduccion.dc.html`).
    enum EmptyState {
        static let topBottomPadding: CGFloat = 28
        static let frameSize: CGFloat = 290
        static let frameBorderWidth: CGFloat = 1.5
        static let frameDash: [CGFloat] = [6, 5]
        static let iconSize: CGFloat = 72
        static let columnGap: CGFloat = 40
        static let blockGap: CGFloat = 28
        static let titleBodyGap: CGFloat = 12
        static let bodyMaxWidth: CGFloat = 400
        static let buttonsGap: CGFloat = 20
        static let primaryButtonHeight: CGFloat = 56
        static let primaryButtonPadding: CGFloat = 28
        static let linkIconSize: CGFloat = 12
        static let linkIconGap: CGFloat = 6
    }
}

extension Palette {
    /// Track of the progress bar (white at 18 %).
    static let progressTrack = Color.white.opacity(0.18)
    /// Icon on the light play button (`#000000` in the mockup).
    static let playButtonIcon = Color.black
    /// Background of an active toggle (shuffle, repeat, lyrics): accent at 16 %.
    static let activeToggleOpacity = 0.16
    /// Dashed frame of "Nada sonando" (white at 30 %).
    static let emptyArtworkBorder = Color.white.opacity(0.3)
}

extension TextStyle {
    /// "Desde la playlist" (13 pt, medium) and the name (13 pt, bold).
    static let originPrefix = TextStyle(size: 13, weight: .medium, scalesWithDynamicType: false)
    static let originName = TextStyle(size: 13, weight: .bold, scalesWithDynamicType: false)
    /// The "Biblioteca" pill.
    static let libraryPill = TextStyle(size: 15, weight: .semibold, scalesWithDynamicType: false)
    /// "Reproduciendo en" (medium) and the device name (bold), 15 pt.
    static let devicePrefix = TextStyle(size: 15, weight: .medium, scalesWithDynamicType: false)
    static let deviceName = TextStyle(size: 15, weight: .bold, scalesWithDynamicType: false)
    /// Small uppercase notice when the data may be old.
    static let freshnessLabel = TextStyle(size: 11, weight: .medium, design: .monospaced,
                                          trackingEm: 0.08, scalesWithDynamicType: false)

    /// "Nada sonando".
    static let emptyTitle = TextStyle(size: 40, weight: .bold, lineHeight: 44, trackingEm: -0.02,
                                      scalesWithDynamicType: false)
    static let emptyBody = TextStyle(size: 17, weight: .regular, lineHeight: 25,
                                     scalesWithDynamicType: false)
    /// "ABRIR SPOTIFY ↗": monospaced 12 pt, medium, tracking +0.08 em.
    static let openSpotifyLink = TextStyle(size: 12, weight: .medium, design: .monospaced,
                                           trackingEm: 0.08, scalesWithDynamicType: false)

    /// The font alone, for `Text` concatenation (where a modifier can't be applied to each
    /// piece). Only for single-line, fixed-size styles.
    var fixedFont: Font {
        .system(size: size, weight: weight, design: design == .monospaced ? .monospaced : .default)
    }
}
