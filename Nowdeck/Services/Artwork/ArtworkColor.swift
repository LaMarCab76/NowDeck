import CoreGraphics
import Foundation

/// The player background taken from the artwork (docs/02-diseno.md, "Fondo según la
/// carátula").
///
/// Two steps, kept apart so the second can follow the theme:
/// 1. `dominantColor(of:)`: the most frequent color of the artwork reduced to 32×32,
///    ignoring almost-black and almost-white pixels. Not the average: the average of a blue
///    and orange cover is a muddy grey that is in neither.
/// 2. `playerBackground(from:readableWith:)`: that color softened to a dark, calm tone that
///    keeps the secondary text readable.
enum ArtworkColor {
    /// Side of the reduced image.
    static let sampleSize = 32
    /// Pixels darker or lighter than this (HSL lightness) are ignored.
    static let nearBlackLightness = 0.08
    static let nearWhiteLightness = 0.92
    /// Saturation is kept between these values…
    static let saturationRange = 0.25...0.35
    /// …unless the color is almost grey: then it stays grey instead of getting an invented hue.
    static let greyThreshold = 0.10
    /// Target lightness, inside the 25–30 % of the design (the mockup's `#34465A` has 28 %).
    static let targetLightness = 0.28
    /// Minimum contrast of the tertiary text (`#A9B4C0` by default) on the background.
    static let minimumContrast = 4.5
    static let darkeningStep = 0.02
    static let minimumLightness = 0.10

    // MARK: Step 1

    /// The dominant color, or `nil` when the artwork is only black and white (the player
    /// then uses the theme background).
    static func dominantColor(of image: CGImage) -> RGBColor? {
        let side = sampleSize
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        // Group similar colors: 4 bits per channel (4096 buckets). Each bucket keeps its
        // count and the sum of its real colors, so the result is the bucket's average and
        // not the corner of the bucket.
        struct Bucket {
            var count = 0
            var red = 0, green = 0, blue = 0
        }
        var buckets: [Int: Bucket] = [:]

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha >= 128 else { continue }
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])

            let maxComponent = max(red, green, blue), minComponent = min(red, green, blue)
            let lightness = Double(maxComponent + minComponent) / 2 / 255
            guard lightness >= nearBlackLightness, lightness <= nearWhiteLightness else { continue }

            let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
            buckets[key, default: Bucket()].count += 1
            buckets[key]!.red += red
            buckets[key]!.green += green
            buckets[key]!.blue += blue
        }

        // Highest count wins; ties go to the lower key so the result is deterministic.
        guard let (_, best) = buckets.max(by: { lhs, rhs in
            lhs.value.count != rhs.value.count ? lhs.value.count < rhs.value.count : lhs.key > rhs.key
        }) else { return nil }

        let count = Double(best.count) * 255
        return RGBColor(red: Double(best.red) / count, green: Double(best.green) / count,
                        blue: Double(best.blue) / count)
    }

    // MARK: Step 2

    /// The softened background for a dominant color. `text` is the color that must stay
    /// readable on it (the theme's tertiary text: times and secondary icons).
    static func playerBackground(from dominant: RGBColor, readableWith text: RGBColor) -> RGBColor {
        var hsl = HSL(dominant)
        if hsl.saturation >= greyThreshold {
            hsl.saturation = min(max(hsl.saturation, saturationRange.lowerBound),
                                 saturationRange.upperBound)
        }
        hsl.lightness = targetLightness

        var color = hsl.rgb
        // Some hues (yellow, green) are brighter at the same lightness: darken until the
        // text passes, in small steps.
        while contrastRatio(text, color) < minimumContrast, hsl.lightness > minimumLightness {
            hsl.lightness = max(minimumLightness, hsl.lightness - darkeningStep)
            color = hsl.rgb
        }
        return color
    }

    // MARK: Contrast (WCAG 2.x)

    static func contrastRatio(_ first: RGBColor, _ second: RGBColor) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func relativeLuminance(_ color: RGBColor) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    // MARK: HSL

    struct HSL: Equatable {
        /// 0..<360.
        var hue: Double
        /// 0...1.
        var saturation: Double
        /// 0...1.
        var lightness: Double

        init(hue: Double, saturation: Double, lightness: Double) {
            self.hue = hue
            self.saturation = saturation
            self.lightness = lightness
        }

        init(_ color: RGBColor) {
            let maxComponent = max(color.red, color.green, color.blue)
            let minComponent = min(color.red, color.green, color.blue)
            let delta = maxComponent - minComponent
            lightness = (maxComponent + minComponent) / 2

            guard delta > 0 else {
                hue = 0
                saturation = 0
                return
            }
            saturation = delta / (1 - abs(2 * lightness - 1))

            var degrees: Double
            switch maxComponent {
            case color.red: degrees = 60 * ((color.green - color.blue) / delta)
            case color.green: degrees = 60 * ((color.blue - color.red) / delta + 2)
            default: degrees = 60 * ((color.red - color.green) / delta + 4)
            }
            if degrees < 0 { degrees += 360 }
            hue = degrees
        }

        var rgb: RGBColor {
            let chroma = (1 - abs(2 * lightness - 1)) * saturation
            let sector = hue / 60
            let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
            let (red, green, blue): (Double, Double, Double)
            switch sector {
            case 0..<1: (red, green, blue) = (chroma, x, 0)
            case 1..<2: (red, green, blue) = (x, chroma, 0)
            case 2..<3: (red, green, blue) = (0, chroma, x)
            case 3..<4: (red, green, blue) = (0, x, chroma)
            case 4..<5: (red, green, blue) = (x, 0, chroma)
            default: (red, green, blue) = (chroma, 0, x)
            }
            let match = lightness - chroma / 2
            func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
            return RGBColor(red: clamp(red + match), green: clamp(green + match),
                            blue: clamp(blue + match))
        }
    }
}
