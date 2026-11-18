import SwiftUI

// Tokens of Agregar a una playlist that Cola does not have (no mockup; owner's request,
// 2026-11-18). The search field is a smaller version of Buscar's (56 tall, white at 10 %):
// the sheet is only 398 tall, and a 56 pt field would leave room for three rows.

extension Metrics {
    enum AddToPlaylist {
        static let searchFieldHeight: CGFloat = 40
        static let searchFieldPadding: CGFloat = 14
        static let searchFieldIconSize: CGFloat = 18
        static let searchFieldIconGap: CGFloat = 10
        /// Between the field and the list.
        static let searchBottomGap: CGFloat = 8
        /// Above "OTRAS PLAYLISTS", after the rows of "YA ESTÁ EN".
        static let sectionTopGap: CGFloat = 12
    }
}

extension TextStyle {
    /// The search field's text and placeholder: 16 pt (Buscar uses 18 in a 56 pt field).
    static let playlistSearchInput = TextStyle(size: 16, weight: .regular,
                                               scalesWithDynamicType: false)
}
