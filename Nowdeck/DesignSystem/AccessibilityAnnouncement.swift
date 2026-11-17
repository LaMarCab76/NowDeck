import SwiftUI
import UIKit

/// VoiceOver announcements for messages that appear on their own and go away: the notices
/// at the top of the screen and the volume panel.
///
/// iOS 16 has no SwiftUI API for this (`AccessibilityNotification.Announcement` is iOS 17),
/// so it goes through `UIAccessibility.post`. Announcements are **queued** instead of
/// interrupting: a notice often appears right after a tap, while VoiceOver is still reading
/// the button that was tapped. Without VoiceOver running, posting does nothing.
@MainActor
enum AccessibilityAnnouncement {
    static func post(_ message: LocalizedStringResource) {
        post(String(localized: message))
    }

    static func post(_ message: String) {
        let queued = NSAttributedString(string: message,
                                        attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: queued)
    }
}
