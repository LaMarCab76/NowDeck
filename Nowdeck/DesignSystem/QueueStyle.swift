import SwiftUI

// Tokens for the inline queue (cola-integrada.html) and the Add to a Playlist sheet.

extension Metrics {
    enum Queue {
        /// Spotify's guidelines: at most 20 items per content row (docs/06).
        static let maxItems = 20

        static let logoSize = CGSize(width: 77, height: 26)
        static let logoClearSpace = logoSize.height / 2

        // Add to a Playlist header
        static let headerArtworkSize: CGFloat = 56
        static let headerGap: CGFloat = 14

        // Rows
        static let rowHeight: CGFloat = 56  // Add to a Playlist
        static let queueRowHeight: CGFloat = 48
        static let rowGap: CGFloat = 14
        static let rowArtworkSize: CGFloat = 40
        static let numberWidth: CGFloat = 20
        static let titleGap: CGFloat = 6
        static let explicitSize: CGFloat = 15
        static let separatorWidth: CGFloat = 1
        static let labelHeight: CGFloat = 22  // Add to a Playlist
        static let queueLabelHeight: CGFloat = 24
        static let fadeHeight: CGFloat = 40  // Add to a Playlist

        // Footer: "Para quitar o reordenar temas, usá Spotify." and "ABRIR SPOTIFY ↗"
        static let footerTopPadding: CGFloat = 6
        static let footerBottomPadding: CGFloat = 12
        static let footerGap: CGFloat = 16

        // Empty queue
        static let emptyMaxWidth: CGFloat = 440
        static let emptyGap: CGFloat = 10
        static let emptyIconSize: CGFloat = 30
        static let emptyBottomPadding: CGFloat = 24  // Add to a Playlist
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
