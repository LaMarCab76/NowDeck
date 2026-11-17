import SwiftUI

// Tokens of the Dispositivos sheet and its help view (Dispositivos.dc.html). Kept in their
// own file, as extensions, so the shared design-system files stay untouched. The handle and
// the close button reuse `Palette.sheetHandle` and `Palette.closeButtonFill`
// (SettingsStyle.swift), which have the same values in this mockup.

extension Metrics {
    enum Devices {
        /// The sheet: 640×398 on 896×414, 16 pt below the top edge.
        static let sheetWidth: CGFloat = 640
        static let sheetTop: CGFloat = 16
        /// Smallest side margin around the sheet (the mockup's 48 pt on narrower screens).
        static let minSideMargin: CGFloat = 48
        static let sheetTopPadding: CGFloat = 10
        static let sheetHorizontalPadding: CGFloat = 28
        static let sheetBottomPadding: CGFloat = 12
        static let sheetGap: CGFloat = 10

        static let handleSize = CGSize(width: 40, height: 5)
        /// Drag distance on the handle that closes the sheet.
        static let dismissDragDistance: CGFloat = 80

        // Header
        static let headerGap: CGFloat = 14
        static let currentCircleSize: CGFloat = 52
        static let currentIconSize: CGFloat = 26
        static let headerTextGap: CGFloat = 2
        static let closeIconSize: CGFloat = 17

        /// Extra space above "ELEGÍ UN DISPOSITIVO" (`margin-top: 6`).
        static let listLabelTopMargin: CGFloat = 6

        // Rows
        static let rowHeight: CGFloat = 60
        static let rowGap: CGFloat = 16
        static let rowIconSize: CGFloat = 26
        static let separatorWidth: CGFloat = 1
        /// Rows that cannot take the playback (restricted devices).
        static let disabledRowOpacity: Double = 0.45

        // "¿No ves tu dispositivo?"
        static let helpButtonIconSize: CGFloat = 20
        static let helpButtonGap: CGFloat = 8
        static let helpButtonPadding: CGFloat = 4

        // Help view
        static let helpVerticalPadding: CGFloat = 20
        static let helpGap: CGFloat = 14
        static let backIconSize: CGFloat = 18
        static let backGap: CGFloat = 6
        static let stepsGap: CGFloat = 12
        static let stepNumberSize: CGFloat = 24
        static let stepNumberBorder: CGFloat = 1.5
        static let refreshButtonHeight: CGFloat = 48
        static let refreshButtonPadding: CGFloat = 24
    }
}

extension Palette {
    /// Lines between device rows (white at 10 %).
    static let deviceSeparator = Color.white.opacity(0.1)
}

extension TextStyle {
    // The sheet has a fixed height (398 pt), like the player, so its text does not follow
    // Dynamic Type: larger sizes would push the rows out of the sheet.

    /// "DISPOSITIVO ACTUAL" and "ELEGÍ UN DISPOSITIVO".
    static let devicesLabel = TextStyle(size: 12, weight: .regular, design: .monospaced,
                                        lineHeight: 16, trackingEm: 0.08,
                                        scalesWithDynamicType: false)
    /// Name of the current device.
    static let currentDeviceName = TextStyle(size: 22, weight: .bold, lineHeight: 28,
                                             scalesWithDynamicType: false)
    /// Device name in a row.
    static let deviceRowName = TextStyle(size: 18, weight: .medium, lineHeight: 24,
                                         scalesWithDynamicType: false)
    /// Device type in a row.
    static let deviceRowType = TextStyle(size: 14, weight: .regular, scalesWithDynamicType: false)
    /// "¿No ves tu dispositivo?" and "Volver a la lista".
    static let devicesTextButton = TextStyle(size: 15, weight: .semibold,
                                             scalesWithDynamicType: false)
    /// Empty list and error messages.
    static let devicesMessage = TextStyle(size: 15, weight: .regular, lineHeight: 21,
                                          scalesWithDynamicType: false)
    /// Help title.
    static let devicesHelpTitle = TextStyle(size: 24, weight: .bold, lineHeight: 30,
                                            trackingEm: -0.01, scalesWithDynamicType: false)
    /// Help steps.
    static let devicesHelpStep = TextStyle(size: 15, weight: .regular, lineHeight: 21,
                                           scalesWithDynamicType: false)
    /// Number inside the step circle.
    static let devicesStepNumber = TextStyle(size: 12, weight: .regular, design: .monospaced,
                                             scalesWithDynamicType: false)
    /// "Actualizar lista".
    static let devicesRefreshButton = TextStyle(size: 16, weight: .bold,
                                                scalesWithDynamicType: false)
}
