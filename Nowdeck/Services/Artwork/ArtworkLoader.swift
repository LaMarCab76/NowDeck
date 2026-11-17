import UIKit

/// Downloads artwork from Spotify's image CDN and computes its dominant color.
///
/// The color is cached per album (or per image URL when there is no album, as with
/// episodes), so going back to a track of the same album costs nothing. Image bytes are
/// cached by `URLSession`'s regular HTTP cache.
actor ArtworkLoader {
    struct Artwork: @unchecked Sendable {
        // `UIImage` is immutable once created; it is only read on the main actor.
        let image: UIImage
        /// `nil` when the cover is only black and white.
        let dominantColor: RGBColor?
    }

    enum LoadError: Error, Equatable {
        case notAnImage
        case http(Int)
        case network(URLError.Code)
    }

    private let session: URLSession
    private var colorCache: [String: RGBColor?] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 100

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// - Parameter cacheKey: the album ID, or `nil` to key by URL.
    func load(_ url: URL, cacheKey: String?) async throws -> Artwork {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw LoadError.network(error.code)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LoadError.http(http.statusCode)
        }
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw LoadError.notAnImage
        }

        let key = cacheKey ?? url.absoluteString
        if let cached = colorCache[key] {
            return Artwork(image: image, dominantColor: cached)
        }
        let color = ArtworkColor.dominantColor(of: cgImage)
        remember(color, for: key)
        return Artwork(image: image, dominantColor: color)
    }

    private func remember(_ color: RGBColor?, for key: String) {
        colorCache[key] = .some(color)
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit {
            colorCache[cacheOrder.removeFirst()] = nil
        }
    }
}
