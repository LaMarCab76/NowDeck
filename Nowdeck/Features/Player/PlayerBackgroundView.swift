import SwiftUI

/// The player's background: the color taken from the cover (or the theme's) and, with
/// "Foto del artista", the artist's photo over the whole screen, like Spotify's TV app
/// (owner's request, 2026-11-17).
///
/// Since 2026-11-18 (owner's request) the photo is alone: it covers the color completely,
/// with no fade toward the cover and no tint at the bottom. The color only shows while the
/// photo loads or when the artist has none. A black layer darkens the photo a bit
/// ("Oscurecer", `oscurecerFondo`) so the text stays readable on bright photos.
///
/// The photo fills the screen, so it is cropped. Spotify's "Get Artist" reference says its
/// visual content "must be kept in its original form, e.g. you can not crop…". The owner
/// decided to show it anyway: it is documented as a gray area in docs/06, and it is only
/// shown with Ajustes → Apariencia → FONDO DEL REPRODUCTOR → "Foto del artista". The cover
/// itself is still shown as Spotify sends it (`ArtworkView`).
struct PlayerBackgroundView: View {
    var color: Color
    var artistImage: UIImage?
    /// The theme's `desenfoqueFondo`, 0 to 100.
    var blur: Int = 0
    /// The theme's `oscurecerFondo`, 0 to 100.
    var dim: Int = Theme.defaultBackgroundDim

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            color
            if let artistImage {
                ArtistPhotoLayer(image: artistImage, drifts: !reduceMotion,
                                 blurRadius: Layout.blurRadius(for: blur),
                                 dimOpacity: Layout.dimOpacity(for: dim))
                    .id(ObjectIdentifier(artistImage))
                    .transition(.opacity)
            }
        }
        .animation(Motion.artistPhotoCrossfade, value: artistImage.map(ObjectIdentifier.init))
        .accessibilityHidden(true)
    }

    private typealias Layout = Metrics.ArtistPhoto
}

/// The photo over the whole screen, blurred and darkened by the theme's values.
private struct ArtistPhotoLayer: View {
    var image: UIImage
    /// A slow zoom in and out (off with Reduce Motion).
    var drifts: Bool
    var blurRadius: CGFloat
    var dimOpacity: CGFloat

    @State private var zoomedIn = false
    private typealias Layout = Metrics.ArtistPhoto

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(zoomedIn ? Layout.driftScale : 1)
                // Opaque: the edges stay solid instead of fading into what is behind.
                .blur(radius: blurRadius, opaque: true)
                .clipped()
        }
        .overlay(Color.black.opacity(dimOpacity))
        .onAppear {
            guard drifts else { return }
            withAnimation(Motion.artistPhotoDrift) { zoomedIn = true }
        }
    }
}

extension Metrics {
    /// The artist's photo behind the player.
    enum ArtistPhoto {
        static let driftScale: CGFloat = 1.06
        /// `desenfoqueFondo` 100 = this radius.
        static let maxBlurRadius: CGFloat = 30
        /// `oscurecerFondo` 100 = black at this opacity: the photo never goes fully black.
        static let maxDimOpacity: CGFloat = 0.8

        static func blurRadius(for value: Int) -> CGFloat {
            maxBlurRadius * fraction(value, in: Theme.backgroundBlurRange)
        }

        static func dimOpacity(for value: Int) -> CGFloat {
            maxDimOpacity * fraction(value, in: Theme.backgroundDimRange)
        }

        private static func fraction(_ value: Int, in range: ClosedRange<Int>) -> CGFloat {
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            return CGFloat(clamped) / CGFloat(range.upperBound)
        }
    }
}

extension Motion {
    /// A new artist: the photos cross-fade.
    static let artistPhotoCrossfade = Animation.easeInOut(duration: 0.8)
    /// Slow zoom, back and forth.
    static let artistPhotoDrift = Animation.easeInOut(duration: 30).repeatForever(autoreverses: true)
}
