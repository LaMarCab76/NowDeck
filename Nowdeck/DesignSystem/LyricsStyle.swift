import SwiftUI

// Design tokens of lyrics mode and the "no lyrics" notice, from `Main.dc.html` (the `letras`
// and `avisoVisible` blocks) and docs/02-diseno.md ("Modo letras", "Aviso").
//
// They live in their own file so the lyrics milestone does not touch the shared design
// system files. The stanza styles themselves (`currentStanza`, `nextStanza`) were already in
// `Typography.swift`.

extension TextStyle {
    /// "Desde la playlist" above the source name: 12/16, weight 500.
    static let lyricsSourceLabel = TextStyle(size: 12, weight: .medium, lineHeight: 16,
                                             scalesWithDynamicType: false)
    /// Name of the playlist or album: 15/20 bold.
    static let lyricsSourceName = TextStyle(size: 15, weight: .bold, lineHeight: 20,
                                            scalesWithDynamicType: false)
    /// Track title in the bottom row: 18/24 bold.
    static let lyricsTrackTitle = TextStyle(size: 18, weight: .bold, lineHeight: 24,
                                            scalesWithDynamicType: false)
    /// Artist in the bottom row: 15/20.
    static let lyricsArtist = TextStyle(size: 15, weight: .regular, lineHeight: 20,
                                        scalesWithDynamicType: false)
    /// Device name in the bottom row: 14 semibold.
    static let lyricsDevice = TextStyle(size: 14, weight: .semibold,
                                        scalesWithDynamicType: false)
    /// Text of the notice pill: 15/20 semibold.
    static let notice = TextStyle(size: 15, weight: .semibold, lineHeight: 20,
                                  scalesWithDynamicType: false)
}

extension Palette {
    /// Text and icon on the light notice pill. The mockup uses pure black on `texto`.
    static let noticeForeground = Color.black
    /// Shadow of the notice pill: `0 8px 28px rgba(0,0,0,0.45)`.
    static let noticeShadow = Color.black.opacity(0.45)
}

extension Metrics {
    enum Lyrics {
        /// Top row: source on the left, Spotify logo on the right.
        static let headerHeight: CGFloat = 44
        static let headerSpacing: CGFloat = 16
        /// Gap between the source icon and its two lines.
        static let headerIconSpacing: CGFloat = 8
        static let headerIconSize: CGFloat = 18
        /// Spotify logo box (same as in the player's normal view).
        static let logoSize = CGSize(width: 108, height: 30)

        /// Gap between the current and the next stanza.
        static let stanzaSpacing: CGFloat = 12

        /// Bottom row: small artwork, title, artist and device.
        static let footerHeight: CGFloat = 56
        static let footerSpacing: CGFloat = 14
        static let artworkSize: CGFloat = 56
        static let titleArtistSpacing: CGFloat = 2
        static let deviceIconSize: CGFloat = 18
        static let deviceIconSpacing: CGFloat = 8
    }

    enum Notice {
        static let height: CGFloat = 48
        /// Distance from the top of the screen.
        static let top: CGFloat = 20
        static let iconSize: CGFloat = 20
        static let iconSpacing: CGFloat = 10
        static let leadingPadding: CGFloat = 16
        static let trailingPadding: CGFloat = 20
        static let shadowRadius: CGFloat = 14
        static let shadowY: CGFloat = 8
        /// How long the notice stays (docs/01-producto.md).
        static let duration: TimeInterval = 3
    }
}
