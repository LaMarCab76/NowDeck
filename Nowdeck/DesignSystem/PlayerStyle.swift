import SwiftUI

// Measurements, colors and text styles of the player (`Main.dc.html`) and "Nada sonando"
// (`SinReproduccion.dc.html`). Kept in their own file, as extensions of the shared design
// system, so that other screens' changes don't collide with these.

extension Metrics {
    /// Player screen (`Main.dc.html`). Margins are in `Spacing.Player`.
    enum Player {
        /// Row across the whole width, at the top: the Spotify icon and "Reproduciendo desde …"
        /// at the left, Biblioteca at the right (owner's request, 2026-11-17: the origin
        /// always in the top-left corner; Ajustes moved to the library).
        static let topRowHeight: CGFloat = 44
        /// Between the top row and the artwork row. The row's 44 pt hold the 36 pt of the
        /// two-line origin, so the visible gap is about 18 pt (owner's request, 2026-11-18:
        /// it was 4 under the origin pill).
        static let topRowBottomGap: CGFloat = 14
        /// Height of the artwork row (artwork and text column). Was 256 before the top row
        /// moved above it, and 216 before the wider gap above; the cover shrinks so
        /// everything still fits in 414 pt.
        static let topBlockHeight: CGFloat = 210
        static let artworkSize: CGFloat = 210
        /// The whole upper area (top row and artwork row). Lyrics mode replaces all of it.
        static let upperAreaHeight: CGFloat = topRowHeight + topRowBottomGap + topBlockHeight
        /// Between the artwork and the text column.
        static let artworkGap: CGFloat = 32
        /// Artwork side on narrow screens: `min(top block height, screen width × 0.3)`
        /// (docs/02-diseno.md, "Adaptación al iPhone 8 Plus").
        static let artworkWidthFraction: CGFloat = 0.3

        /// Between the origin, Cola and Biblioteca. Wider than the 12 of the old pills: without
        /// a background, the buttons need the space to read as two.
        static let topRowGap: CGFloat = 24
        /// Full Spotify logo (Biblioteca): 108×30 inside a 44 pt tap zone.
        static let logoSize = CGSize(width: 108, height: 30)
        /// Spotify icon next to the origin (owner's decision, 2026-11-17: the icon
        /// instead of the full logo, in the normal view and in lyrics mode). Spotify's minimum
        /// for the icon alone is 21 px.
        static let iconSize: CGFloat = 24
        /// Space between the icon and the origin: half the icon height, as Spotify's
        /// guidelines ask for the clear space (docs/06).
        static let iconClearSpace: CGFloat = 12
        static let libraryPillLeadingPadding: CGFloat = 12
        static let libraryPillTrailingPadding: CGFloat = 16
        static let libraryPillIconGap: CGFloat = 8
        static let libraryIconSize: CGFloat = 20
        /// The symbol on the empty cover of a swipe preview (next or previous unknown).
        static let previewSymbolSize: CGFloat = 40

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
        /// Extra tappable margin around the time on the right (16 pt row + 2 × 14 ≈ 44 pt).
        static let progressTimeTapOutset: CGFloat = 14
        static let progressBarHeight: CGFloat = 4
        /// The bar while a finger drags on it.
        static let progressBarScrubbingHeight: CGFloat = 8
        /// The bar takes the finger this far above and below its 16 pt row (16 + 2 × 14 ≈
        /// 44 pt, the minimum touch target).
        static let progressBarTouchOutset: CGFloat = 14

        static let controlsHeight: CGFloat = 64
        /// One centered row with the same gap between every button (owner's request,
        /// 2026-11-17), instead of the mockup's three groups pinned to the edges. With the
        /// default seven buttons the row is 584 pt wide: it fits the 640 pt of the 8 Plus.
        static let controlsGap: CGFloat = 36
        /// The gap shrinks toward this on narrow screens, where Agregar a una playlist would
        /// not fit with 36 (`PlayerControlLayout.gap(forWidth:)`).
        static let controlsMinimumGap: CGFloat = 12
        static let sideButtonSize: CGFloat = 48
        static let sideIconSize: CGFloat = 22
        static let skipButtonSize: CGFloat = 56
        static let skipIconSize: CGFloat = 28
        static let playButtonSize: CGFloat = 64
        static let playIconSize: CGFloat = 26
        /// previous · play/pause · next (or −15 s · play/pause · +15 s), without the gaps.
        static let centerGroupWidth: CGFloat = skipButtonSize + playButtonSize + skipButtonSize
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
    /// "Reproduciendo desde" over the source's name, in two lines and without a pill
    /// (2026-11-18). The same sizes as the source in lyrics mode (12/16 medium, 15/20 bold),
    /// so both views match; 36 pt in all.
    static let originHeading = lyricsSourceLabel
    static let originName = lyricsSourceName
    /// "Biblioteca" and "Cola".
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
