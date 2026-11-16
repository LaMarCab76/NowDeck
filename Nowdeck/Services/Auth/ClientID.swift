import Foundation

/// The Client ID of the user's own Spotify developer app.
enum ClientID {
    static let length = 32

    /// Cleans pasted text: Client IDs never contain spaces or line breaks, but copying from a
    /// web page often adds them around the value.
    static func normalized(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /// 32 ASCII letters and digits (docs/07-plan.md). Spotify shows them as lowercase hex,
    /// but we accept any ASCII alphanumeric so a future change in format does not lock users out.
    static func isValid(_ text: String) -> Bool {
        text.count == length && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
