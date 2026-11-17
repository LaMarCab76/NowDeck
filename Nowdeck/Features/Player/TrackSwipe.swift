import SwiftUI

/// The horizontal swipe that changes track (owner's request, 2026-11-17), like a carousel:
/// dragging left plays the next item of the queue, dragging right the previous one. The
/// cover, title and device row follow the finger and the other item slides in from the side
/// it comes from (`TrackSwipePhase`, `PlayerView`).
///
/// It starts anywhere in the band of the cover and title, from screen edge to screen edge:
/// the normal view's cover, title and device, or the bottom row of lyrics mode (never on the
/// lyrics). Only drags that start more horizontal than vertical count. The progress bar and
/// the controls are outside the band, so their own drags are untouched.
///
/// Pure logic, so it can be tested without touches.
struct TrackSwipe: Equatable {
    /// The side the other item comes in from.
    enum Edge: Equatable {
        /// Dragging right: the previous item comes in from the left.
        case left
        /// Dragging left: the next item comes in from the right.
        case right
    }

    /// How far the finger has to move.
    static let commitDistance: CGFloat = 96
    /// A quick flick commits earlier: when its predicted end goes this much further.
    static let flickDistance: CGFloat = 2 * commitDistance
    /// Movement before the direction is judged (horizontal or vertical).
    static let decisionDistance: CGFloat = 8

    let edge: Edge
    /// Distance moved, never negative.
    let distance: CGFloat

    /// `translation` is the horizontal movement since the touch began. It can change side
    /// mid-drag: going back past the start shows the other item.
    init(translation: CGFloat) {
        edge = translation < 0 ? .right : .left
        distance = abs(translation)
    }

    /// Whether a touch that starts at `point` (window coordinates) and has moved
    /// `translation` so far is a track swipe. `band` is the vertical span of the cover and
    /// title, `nil` when they are not on screen.
    static func canStart(at point: CGPoint, translation: CGSize,
                         band: ClosedRange<CGFloat>?) -> Bool {
        guard abs(translation.width) > abs(translation.height),
              let band
        else { return false }
        return band.contains(point.y)
    }

    var isCommitted: Bool { distance >= Self.commitDistance }

    /// On release: committed, or flicked fast enough in the same direction
    /// (`predictedTranslation` from SwiftUI's predicted end location).
    func commitsOnRelease(predictedTranslation: CGFloat) -> Bool {
        if isCommitted { return true }
        let predicted = edge == .right ? -predictedTranslation : predictedTranslation
        return predicted >= Self.flickDistance
    }
}

/// Where the swipe is, for the player to draw it.
enum TrackSwipePhase: Equatable {
    case idle
    /// The finger is down. `isAllowed` is `false` when Spotify forbids that skip: the content
    /// then resists and nothing happens on release.
    case dragging(edge: TrackSwipe.Edge, distance: CGFloat, isAllowed: Bool)
    /// Released past the threshold: the other item sits in the middle until Spotify reports
    /// it (`PlayerContent` then goes back to `idle` without animation). `preview` is frozen
    /// at release, so a new queue read cannot change the card meanwhile; `fromKey` is the
    /// item that was playing.
    case landing(edge: TrackSwipe.Edge, preview: TrackPreview?, fromKey: String?)

    var edge: TrackSwipe.Edge? {
        switch self {
        case .idle: return nil
        case .dragging(let edge, _, _), .landing(let edge, _, _): return edge
        }
    }

    var isLanding: Bool {
        if case .landing = self { return true }
        return false
    }

    /// Horizontal shift of the current cover and title. The preview sits one `pageWidth`
    /// further, on the side of `edge`.
    func offset(pageWidth: CGFloat) -> CGFloat {
        switch self {
        case .idle:
            return 0
        case let .dragging(edge, distance, isAllowed):
            let moved = min(isAllowed ? distance : Self.resisted(distance), pageWidth)
            return edge == .right ? -moved : moved
        case .landing(let edge, _, _):
            return edge == .right ? -pageWidth : pageWidth
        }
    }

    /// Where the page of the other item sits.
    func previewOffset(pageWidth: CGFloat) -> CGFloat {
        offset(pageWidth: pageWidth) + (edge == .right ? pageWidth : -pageWidth)
    }

    /// A forbidden skip moves a third as far, and never more than `maxResisted`.
    static func resisted(_ distance: CGFloat) -> CGFloat {
        min(distance / 3, maxResisted)
    }

    static let maxResisted: CGFloat = 40
}

/// The cover and title band in window coordinates, reported by `PlayerView` or
/// `LyricsModeView` so the full screen gesture knows where a swipe may start.
struct TrackSwipeBandKey: PreferenceKey {
    static let defaultValue: ClosedRange<CGFloat>? = nil
    static func reduce(value: inout ClosedRange<CGFloat>?, nextValue: () -> ClosedRange<CGFloat>?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Reports track swipes (see `TrackSwipe`). `onEnd` gets the swipe and whether its
    /// release commits it.
    func trackSwipe(isActive: Bool, band: ClosedRange<CGFloat>?,
                    onChange: @escaping (TrackSwipe) -> Void,
                    onEnd: @escaping (TrackSwipe, _ commits: Bool) -> Void) -> some View {
        modifier(TrackSwipeModifier(isActive: isActive, band: band,
                                    onChange: onChange, onEnd: onEnd))
    }
}

private struct TrackSwipeModifier: ViewModifier {
    var isActive: Bool
    var band: ClosedRange<CGFloat>?
    var onChange: (TrackSwipe) -> Void
    var onEnd: (TrackSwipe, Bool) -> Void

    /// Decided once per touch, after `decisionDistance`: `true` for a track swipe.
    @State private var isSwiping: Bool?

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(drag, including: isActive ? .all : .subviews)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: TrackSwipe.decisionDistance, coordinateSpace: .global)
            .onChanged { value in
                if isSwiping == nil {
                    isSwiping = TrackSwipe.canStart(at: value.startLocation,
                                                    translation: value.translation, band: band)
                }
                guard isSwiping == true else { return }
                onChange(TrackSwipe(translation: value.translation.width))
            }
            .onEnded { value in
                defer { isSwiping = nil }
                guard isSwiping == true else { return }
                let swipe = TrackSwipe(translation: value.translation.width)
                let predicted = value.predictedEndLocation.x - value.startLocation.x
                onEnd(swipe, swipe.commitsOnRelease(predictedTranslation: predicted))
            }
    }
}

extension View {
    /// Reports this view's vertical span as the band where a track swipe can start.
    func trackSwipeBand() -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear.preference(key: TrackSwipeBandKey.self, value: frame.minY...frame.maxY)
            }
        }
    }
}
