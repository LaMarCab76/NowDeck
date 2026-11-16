import SwiftUI

/// An opaque sRGB color, parsed from `#RRGGBB`.
///
/// It is kept separate from `SwiftUI.Color` because `Color` cannot be compared reliably
/// nor inspected, and we need both: tests compare tokens, and the theme validation and
/// artwork background (later milestones) need the components for contrast math.
struct RGBColor: Equatable, Hashable, Sendable {
    /// Components in 0...1.
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `#RRGGBB` (case-insensitive). Anything else, including `#RGB`, returns `nil`.
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#" else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Uppercase `#RRGGBB`.
    var hexString: String {
        func byte(_ component: Double) -> Int { Int((component * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
