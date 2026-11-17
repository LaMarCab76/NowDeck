import SwiftUI

// Tokens of the Cola sheet (Cola.html). The sheet itself (640×398, handle, close button,
// margins) has the same values as Dispositivos and reuses `Metrics.Devices`; rows reuse the
// track styles of the playlist detail (`trackRowTitle`, `cardSubtitle`, `trackRowNumber`).

extension Metrics {
    enum Queue {
        /// Spotify's guidelines: at most 20 items per content row (docs/06).
        static let maxItems = 20

        // Header
        static let headerArtworkSize: CGFloat = 56
        static let headerGap: CGFloat = 14

        // Rows
        static let rowHeight: CGFloat = 56
        static let rowGap: CGFloat = 14
        static let rowArtworkSize: CGFloat = 40
        static let numberWidth: CGFloat = 20
        static let titleGap: CGFloat = 6
        static let explicitSize: CGFloat = 15
        static let separatorWidth: CGFloat = 1
        /// "A CONTINUACIÓN" sits in a 22 pt band, like the detail's list label.
        static let labelHeight: CGFloat = 22
        /// The bottom fade over the list.
        static let fadeHeight: CGFloat = 40

        // Footer: "Para quitar o reordenar temas, usá Spotify." and "ABRIR SPOTIFY ↗"
        static let footerTopPadding: CGFloat = 6
        static let footerBottomPadding: CGFloat = 12
        static let footerGap: CGFloat = 16

        // Empty queue
        static let emptyMaxWidth: CGFloat = 440
        static let emptyGap: CGFloat = 10
        static let emptyIconSize: CGFloat = 30
        static let emptyBottomPadding: CGFloat = 24
    }
}

extension TextStyle {
    // Fixed sheet height, like Dispositivos: no Dynamic Type.

    /// Title of the item playing now: 20 pt bold, line height 26.
    static let queueCurrentTitle = TextStyle(size: 20, weight: .bold, lineHeight: 26,
                                             scalesWithDynamicType: false)
    /// Its artists or podcast: 14 pt, line height 18.
    static let queueCurrentSubtitle = TextStyle(size: 14, weight: .regular, lineHeight: 18,
                                                scalesWithDynamicType: false)
    /// The footer explanation: 14 pt, line height 20.
    static let queueFooter = TextStyle(size: 14, weight: .regular, lineHeight: 20,
                                       scalesWithDynamicType: false)
    /// "No hay nada en la cola": 20 pt bold, line height 26.
    static let queueEmptyTitle = TextStyle(size: 20, weight: .bold, lineHeight: 26,
                                           scalesWithDynamicType: false)
    /// The empty queue's explanation: 15 pt, line height 22.
    static let queueEmptyBody = TextStyle(size: 15, weight: .regular, lineHeight: 22,
                                          scalesWithDynamicType: false)
}
