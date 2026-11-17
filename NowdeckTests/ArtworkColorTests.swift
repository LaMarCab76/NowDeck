import CoreGraphics
import XCTest
@testable import Nowdeck

final class ArtworkColorTests: XCTestCase {
    private let tertiaryText = RGBColor(hex: "#A9B4C0")!

    /// A 64×64 test image made of horizontal bands: (color, share of the height).
    private func image(_ bands: [(String, Double)]) -> CGImage {
        let side = 64
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var y = 0.0
        for (hex, share) in bands {
            let color = RGBColor(hex: hex)!
            context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
            let height = Double(side) * share
            context.fill(CGRect(x: 0, y: y, width: Double(side), height: height))
            y += height
        }
        return context.makeImage()!
    }

    private func assertClose(_ color: RGBColor?, _ hex: String, tolerance: Double = 2.0 / 255,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let color, let expected = RGBColor(hex: hex) else {
            return XCTFail("Missing color", file: file, line: line)
        }
        XCTAssertEqual(color.red, expected.red, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(color.green, expected.green, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(color.blue, expected.blue, accuracy: tolerance, file: file, line: line)
    }

    // MARK: Dominant color

    func testSolidCover() {
        assertClose(ArtworkColor.dominantColor(of: image([("#1E3A5C", 1)])), "#1E3A5C")
    }

    /// The mockup's cover: blue sky with an orange sun. The most frequent color wins; the
    /// average would be a grey that is in neither.
    func testMostFrequentColorWinsOverTheAverage() {
        let cover = image([("#1E3A5C", 0.6), ("#F0A24E", 0.4)])
        assertClose(ArtworkColor.dominantColor(of: cover), "#1E3A5C")
    }

    func testNearBlackAndNearWhiteAreIgnored() {
        let cover = image([("#000000", 0.5), ("#FFFFFF", 0.35), ("#2FA05A", 0.15)])
        assertClose(ArtworkColor.dominantColor(of: cover), "#2FA05A")
    }

    func testBlackAndWhiteCoverHasNoColor() {
        XCTAssertNil(ArtworkColor.dominantColor(of: image([("#000000", 0.5), ("#FFFFFF", 0.5)])))
    }

    // MARK: Softened background

    func testBackgroundIsDarkAndCalm() {
        for hex in ["#F0A24E", "#1E3A5C", "#E62E2E", "#7CC4FF", "#C9A2FF"] {
            let background = ArtworkColor.playerBackground(from: RGBColor(hex: hex)!,
                                                           readableWith: tertiaryText)
            let hsl = ArtworkColor.HSL(background)
            XCTAssertTrue((0.25 - 0.005...0.35 + 0.005).contains(hsl.saturation),
                          "\(hex): saturation \(hsl.saturation)")
            XCTAssertLessThanOrEqual(hsl.lightness, 0.30 + 0.005, hex)
            XCTAssertGreaterThanOrEqual(
                ArtworkColor.contrastRatio(tertiaryText, background), 4.5, hex)
        }
    }

    /// The mockup's example background `#34465A` has 27 % saturation and 28 % lightness:
    /// starting from it gives (almost) the same color.
    func testMockupBackgroundIsStable() {
        let background = ArtworkColor.playerBackground(from: RGBColor(hex: "#34465A")!,
                                                       readableWith: tertiaryText)
        assertClose(background, "#34465A", tolerance: 3.0 / 255)
    }

    /// Bright hues are darkened until the tertiary text reaches 4.5:1.
    func testBrightHueIsDarkenedForContrast() {
        let background = ArtworkColor.playerBackground(from: RGBColor(hex: "#F5E663")!,
                                                       readableWith: tertiaryText)
        XCTAssertGreaterThanOrEqual(ArtworkColor.contrastRatio(tertiaryText, background), 4.5)
        XCTAssertLessThan(ArtworkColor.HSL(background).lightness, 0.28)
    }

    func testGreyCoverStaysGrey() {
        let background = ArtworkColor.playerBackground(from: RGBColor(hex: "#808080")!,
                                                       readableWith: tertiaryText)
        XCTAssertEqual(ArtworkColor.HSL(background).saturation, 0, accuracy: 0.001)
    }

    func testContrastRatio() {
        XCTAssertEqual(ArtworkColor.contrastRatio(RGBColor(hex: "#FFFFFF")!, RGBColor(hex: "#000000")!),
                       21, accuracy: 0.01)
        // Value from docs/02-diseno.md: textoTerciario on #34465A is 4.6:1.
        XCTAssertEqual(ArtworkColor.contrastRatio(tertiaryText, RGBColor(hex: "#34465A")!),
                       4.6, accuracy: 0.1)
    }

    func testHSLRoundTrip() {
        for hex in ["#34465A", "#F0A24E", "#2FD566", "#000000", "#FFFFFF"] {
            let color = RGBColor(hex: hex)!
            assertClose(ArtworkColor.HSL(color).rgb, hex, tolerance: 1.0 / 255)
        }
    }
}
