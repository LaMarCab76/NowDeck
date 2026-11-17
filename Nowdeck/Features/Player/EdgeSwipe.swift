import SwiftUI
import UIKit

/// A drag that starts next to the left or right edge of the screen (owner's request,
/// 2026-11-17): from the right edge toward the center plays the next item of the queue, from
/// the left edge the previous one. The cover and title follow the finger and the other item
/// slides in from that edge (`TrackSwipePhase`, `PlayerView`).
///
/// Pure logic, so it can be tested without touches. The edges are physical (left and
/// right), as the screen is always in landscape and the app is only in Spanish for now.
struct EdgeSwipe: Equatable {
    enum Edge: Equatable {
        /// Starts at the left edge and moves right: previous.
        case left
        /// Starts at the right edge and moves left: next.
        case right
    }

    /// How close to the edge the finger has to land. The player's margins are 48 pt, so no
    /// button sits inside this zone.
    static let edgeZone: CGFloat = 40
    /// How far the finger has to move away from the edge.
    static let commitDistance: CGFloat = 96
    /// A quick flick commits earlier: when its predicted end goes this much further.
    static let flickDistance: CGFloat = 2 * commitDistance

    let edge: Edge
    /// Distance moved away from the edge, never negative.
    let distance: CGFloat

    /// `nil` when the touch did not start next to an edge.
    init?(startX: CGFloat, currentX: CGFloat, screenWidth: CGFloat) {
        guard screenWidth > 2 * Self.edgeZone else { return nil }
        if startX <= Self.edgeZone {
            edge = .left
            distance = max(0, currentX - startX)
        } else if startX >= screenWidth - Self.edgeZone {
            edge = .right
            distance = max(0, startX - currentX)
        } else {
            return nil
        }
    }

    /// 0 at the edge, 1 once the release would trigger the action.
    var progress: CGFloat { min(1, distance / Self.commitDistance) }

    var isCommitted: Bool { distance >= Self.commitDistance }

    /// On release: committed, or flicked fast enough (`predictedX` is SwiftUI's predicted end
    /// location).
    func commitsOnRelease(predictedX: CGFloat, startX: CGFloat) -> Bool {
        if isCommitted { return true }
        let predicted = edge == .left ? predictedX - startX : startX - predictedX
        return predicted >= Self.flickDistance
    }
}

/// Where the swipe is, for the player to draw it.
enum TrackSwipePhase: Equatable {
    case idle
    /// The finger is down. `isAllowed` is `false` when Spotify forbids that skip: the content
    /// then resists and nothing happens on release.
    case dragging(edge: EdgeSwipe.Edge, distance: CGFloat, isAllowed: Bool)
    /// Released past the threshold: the other item sits in the middle until Spotify reports
    /// it (`PlayerContent` then goes back to `idle` without animation). `preview` is frozen
    /// at release, so a new queue read cannot change the card meanwhile; `fromKey` is the
    /// item that was playing.
    case landing(edge: EdgeSwipe.Edge, preview: TrackPreview?, fromKey: String?)

    var edge: EdgeSwipe.Edge? {
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

    /// A forbidden skip moves a third as far, and never more than `maxResisted`.
    static func resisted(_ distance: CGFloat) -> CGFloat {
        min(distance / 3, maxResisted)
    }

    static let maxResisted: CGFloat = 40
}

extension View {
    /// Reports drags that start at the left or right edge of the screen. `onChange` gets
    /// `nil` for drags that started elsewhere; `onEnd` gets the swipe and whether its release
    /// commits it.
    func edgeSwipe(isActive: Bool,
                   onChange: @escaping (EdgeSwipe) -> Void,
                   onEnd: @escaping (EdgeSwipe, _ commits: Bool) -> Void) -> some View {
        modifier(EdgeSwipeModifier(isActive: isActive, onChange: onChange, onEnd: onEnd))
    }
}

private struct EdgeSwipeModifier: ViewModifier {
    var isActive: Bool
    var onChange: (EdgeSwipe) -> Void
    var onEnd: (EdgeSwipe, Bool) -> Void

    @State private var screenWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                // Full screen, safe area included: the drag reports window coordinates.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { screenWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { screenWidth = $0 }
                }
                .ignoresSafeArea()
            }
            .simultaneousGesture(drag, including: isActive ? .all : .subviews)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard let swipe = EdgeSwipe(startX: value.startLocation.x,
                                            currentX: value.location.x,
                                            screenWidth: screenWidth)
                else { return }
                onChange(swipe)
            }
            .onEnded { value in
                guard let swipe = EdgeSwipe(startX: value.startLocation.x,
                                            currentX: value.location.x,
                                            screenWidth: screenWidth)
                else { return }
                onEnd(swipe, swipe.commitsOnRelease(predictedX: value.predictedEndLocation.x,
                                                    startX: value.startLocation.x))
            }
    }
}
