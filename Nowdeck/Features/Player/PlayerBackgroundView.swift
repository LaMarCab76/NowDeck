import SwiftUI

/// The player's background: the color taken from the cover (or the theme's) and, on top of
/// it, the artist's photo, like Spotify's TV app (owner's request, 2026-11-17).
///
/// The photo fills the screen, so it is cropped, and it is faded into the color. Spotify's
/// "Get Artist" reference says its visual content "must be kept in its original form, e.g.
/// you can not crop…". The owner decided to show it anyway: it is documented as a gray area
/// in docs/06, and Ajustes → Apariencia can turn it off. The cover itself is still shown as
/// Spotify sends it (`ArtworkView`).
struct PlayerBackgroundView: View {
    var color: Color
    var artistImage: UIImage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            color
            if let artistImage {
                ArtistPhotoLayer(image: artistImage, tint: color, drifts: !reduceMotion)
                    .id(ObjectIdentifier(artistImage))
                    .transition(.opacity)
            }
        }
        .animation(Motion.artistPhotoCrossfade, value: artistImage.map(ObjectIdentifier.init))
        .accessibilityHidden(true)
    }
}

/// The photo, strongest at the right and faded out toward the cover at the left, with the
/// bottom blended into the color so the progress bar and the controls stay readable.
private struct ArtistPhotoLayer: View {
    var image: UIImage
    var tint: Color
    /// A slow zoom in and out (off with Reduce Motion).
    var drifts: Bool

    @State private var zoomedIn = false
    private typealias Layout = Metrics.ArtistPhoto

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(zoomedIn ? Layout.driftScale : 1)
                .clipped()
                .opacity(Layout.opacity)
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: Layout.fadeStart),
                        .init(color: .black, location: Layout.fadeEnd),
                    ], startPoint: .leading, endPoint: .trailing)
                )
        }
        .overlay(
            LinearGradient(colors: [tint.opacity(0), tint.opacity(Layout.bottomTintOpacity)],
                           startPoint: .center, endPoint: .bottom)
        )
        .onAppear {
            guard drifts else { return }
            withAnimation(Motion.artistPhotoDrift) { zoomedIn = true }
        }
    }
}

extension Metrics {
    /// The artist's photo behind the player.
    enum ArtistPhoto {
        /// Over the cover color. Higher values make the title harder to read on bright photos.
        static let opacity: CGFloat = 0.45
        /// Horizontal fade (fractions of the width): hidden at the left, behind the cover, and
        /// fully visible from about the middle of the text column.
        static let fadeStart: CGFloat = 0.12
        static let fadeEnd: CGFloat = 0.6
        /// The bottom half fades back into the color, behind progress and controls.
        static let bottomTintOpacity: CGFloat = 0.85
        static let driftScale: CGFloat = 1.06
    }
}

extension Motion {
    /// A new artist: the photos cross-fade.
    static let artistPhotoCrossfade = Animation.easeInOut(duration: 0.8)
    /// Slow zoom, back and forth.
    static let artistPhotoDrift = Animation.easeInOut(duration: 30).repeatForever(autoreverses: true)
}
