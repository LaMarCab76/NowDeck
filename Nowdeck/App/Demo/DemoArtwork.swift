#if DEBUG
import UIKit

/// Covers drawn on the fly for the demo: a two-color gradient with one simple shape. No real
/// artwork is ever used.
///
/// The URL carries the whole recipe, `https://demo.nowdeck.invalid/art/<from>-<to>-<shape>.png`
/// (colors as 6-digit hex), so `DemoContent` picks each cover explicitly and the same URL
/// always gives the same image. `.invalid` is a reserved domain that never resolves.
enum DemoArtwork {
    static let host = "demo.nowdeck.invalid"

    enum Shape: String, CaseIterable {
        /// A big pale circle low in the frame.
        case sun
        /// Concentric outlined circles.
        case rings
        /// Horizontal bars of decreasing width.
        case stripes
        /// A grid of small dots.
        case dots
        /// Only the gradient.
        case plain
    }

    static func url(from: String, to: String, shape: Shape) -> String {
        "https://\(host)/art/\(from)-\(to)-\(shape.rawValue).png"
    }

    /// PNG data for a cover path such as `/art/1b2a4a-f2766b-sun.png`. `nil` when the path
    /// is not one of ours.
    static func png(forPath path: String, side: CGFloat = 640) -> Data? {
        guard path.hasPrefix("/art/"), path.hasSuffix(".png") else { return nil }
        let recipe = path.dropFirst("/art/".count).dropLast(".png".count)
        let parts = recipe.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let from = color(hex: parts[0]), let to = color(hex: parts[1]),
              let shape = Shape(rawValue: parts[2])
        else { return nil }
        return render(from: from, to: to, shape: shape, side: side)
    }

    /// The cover for a demo URL, for views that cannot use the demo session (`AsyncImage`).
    /// `nil` for any other URL.
    @MainActor
    static func image(for url: URL?) -> UIImage? {
        guard let url, url.host == host else { return nil }
        if let cached = imageCache[url.path] { return cached }
        guard let data = png(forPath: url.path, side: 300), let image = UIImage(data: data)
        else { return nil }
        imageCache[url.path] = image
        return image
    }

    @MainActor private static var imageCache: [String: UIImage] = [:]

    private static func render(from: UIColor, to: UIColor, shape: Shape, side: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { context in
            let cg = context.cgContext
            let colors = [from.cgColor, to.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                      locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side),
                                  options: [])

            let ink = UIColor(white: 1, alpha: 0.82)
            switch shape {
            case .sun:
                ink.withAlphaComponent(0.75).setFill()
                let diameter = side * 0.46
                cg.fillEllipse(in: CGRect(x: (side - diameter) / 2, y: side * 0.40,
                                          width: diameter, height: diameter))
                UIColor(white: 0, alpha: 0.18).setFill()
                cg.fill(CGRect(x: 0, y: side * 0.72, width: side, height: side * 0.28))
            case .rings:
                ink.withAlphaComponent(0.6).setStroke()
                cg.setLineWidth(side * 0.018)
                for index in 1...6 {
                    let radius = side * 0.07 * CGFloat(index)
                    cg.strokeEllipse(in: CGRect(x: side / 2 - radius, y: side / 2 - radius,
                                                width: radius * 2, height: radius * 2))
                }
            case .stripes:
                ink.withAlphaComponent(0.55).setFill()
                for index in 0..<6 {
                    let width = side * (0.72 - 0.1 * CGFloat(index))
                    cg.fill(CGRect(x: side * 0.14, y: side * (0.2 + 0.1 * CGFloat(index)),
                                   width: width, height: side * 0.045))
                }
            case .dots:
                ink.withAlphaComponent(0.5).setFill()
                let step = side / 8
                for row in 1..<8 {
                    for column in 1..<8 {
                        let radius = side * 0.016 * CGFloat(1 + (row + column) % 3)
                        cg.fillEllipse(in: CGRect(x: step * CGFloat(column) - radius,
                                                  y: step * CGFloat(row) - radius,
                                                  width: radius * 2, height: radius * 2))
                    }
                }
            case .plain:
                break
            }
        }
    }

    private static func color(hex: String) -> UIColor? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }
}
#endif
