import SwiftUI

/// Shared animations for track and lyrics changes (owner's request, 2026-11-17). They are not
/// in the mockups, so they stay short and soft: fades and small vertical moves, never on the
/// artwork itself beyond a cross-fade. With Reduce Motion only the fades remain.
enum Motion {
    /// Title, artist and origin when a new track starts.
    static let trackChange = Animation.easeInOut(duration: 0.35)
    /// One cover fading into the next.
    static let artworkCrossfade = Animation.easeInOut(duration: 0.45)
    /// Normal view ⇄ lyrics mode.
    static let modeChange = Animation.easeInOut(duration: 0.3)
    /// The current stanza leaving upward while the next one comes in.
    static let stanzaChange = Animation.easeOut(duration: 0.35)

    /// How far texts move when they change.
    static let trackRise: CGFloat = 10
    static let stanzaRise: CGFloat = 18

    /// The new content rises into place while the old one rises away; both fade.
    static func rise(_ distance: CGFloat, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: distance)),
            removal: .opacity.combined(with: .offset(y: -distance))
        )
    }
}

extension NowPlaying {
    /// Changes when another track or episode starts; drives the track-change animations.
    var transitionKey: String {
        itemURL?.absoluteString ?? "\(title)|\(subtitle)"
    }
}
