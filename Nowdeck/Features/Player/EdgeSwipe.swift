import SwiftUI
import UIKit

/// A drag that starts next to the left or right edge of the screen (owner's request,
/// 2026-11-17): from the right edge toward the center plays the next track, from the left
/// edge the previous one. On podcast episodes it seeks ±15 s, like the buttons.
///
/// Pure logic, so it can be tested without touches. The edges are physical (left and
/// right), as the screen is always in landscape and the app is only in Spanish for now.
struct EdgeSwipe: Equatable {
    enum Edge: Equatable {
        /// Starts at the left edge and moves right: previous (or −15 s).
        case left
        /// Starts at the right edge and moves left: next (or +15 s).
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

extension View {
    /// Adds the edge swipe to the player. `isEnabled` follows `ControlAvailability`: a
    /// forbidden action shows the indicator dimmed and does nothing on release.
    func edgeSwipe(isActive: Bool, isEpisode: Bool,
                   isEnabled: @escaping (EdgeSwipe.Edge) -> Bool,
                   onCommit: @escaping (EdgeSwipe.Edge) -> Void) -> some View {
        modifier(EdgeSwipeModifier(isActive: isActive, isEpisode: isEpisode,
                                   isEnabled: isEnabled, onCommit: onCommit))
    }
}

private struct EdgeSwipeModifier: ViewModifier {
    var isActive: Bool
    var isEpisode: Bool
    var isEnabled: (EdgeSwipe.Edge) -> Bool
    var onCommit: (EdgeSwipe.Edge) -> Void

    @State private var swipe: EdgeSwipe?
    @State private var screenWidth: CGFloat = 0
    @EnvironmentObject private var theme: ThemeStore

    private typealias Layout = Metrics.EdgeSwipeIndicator

    func body(content: Content) -> some View {
        content
            .overlay {
                // Full screen, safe area included: the drag reports window coordinates and
                // the indicators slide in from the physical edges.
                GeometryReader { proxy in
                    ZStack {
                        indicator(for: .left, screen: proxy.size)
                        indicator(for: .right, screen: proxy.size)
                    }
                    .onAppear { screenWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { screenWidth = $0 }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .simultaneousGesture(drag, including: isActive ? .all : .subviews)
            .onChange(of: swipe?.isCommitted == true) { committed in
                if committed, let edge = swipe?.edge, isEnabled(edge) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                swipe = EdgeSwipe(startX: value.startLocation.x, currentX: value.location.x,
                                  screenWidth: screenWidth)
            }
            .onEnded { value in
                defer { withAnimation(.easeOut(duration: 0.2)) { swipe = nil } }
                guard let current = EdgeSwipe(startX: value.startLocation.x,
                                              currentX: value.location.x,
                                              screenWidth: screenWidth),
                      current.commitsOnRelease(predictedX: value.predictedEndLocation.x,
                                               startX: value.startLocation.x),
                      isEnabled(current.edge)
                else { return }
                onCommit(current.edge)
            }
    }

    private func indicator(for edge: EdgeSwipe.Edge, screen: CGSize) -> some View {
        let progress = swipe?.edge == edge ? swipe?.progress ?? 0 : 0
        let enabled = isEnabled(edge)
        let highlighted = enabled && swipe?.edge == edge && swipe?.isCommitted == true
        // Center distance from the edge: hidden past it at 0, `inset` inside it at 1.
        let fromEdge = (Layout.size + Layout.inset) * progress - Layout.size / 2
        return Image(systemName: symbol(for: edge))
            .font(.system(size: Layout.iconSize, weight: .semibold))
            .foregroundStyle(highlighted ? Palette.playButtonIcon : theme.palette.text.color)
            .frame(width: Layout.size, height: Layout.size)
            .background(Circle().fill(highlighted ? theme.palette.text.color
                                                  : Palette.edgeSwipeIndicator))
            .opacity(progress * (enabled ? 1 : Palette.disabledControlOpacity))
            .animation(.easeOut(duration: 0.15), value: highlighted)
            .position(x: edge == .left ? fromEdge : screen.width - fromEdge,
                      y: screen.height / 2)
    }

    private func symbol(for edge: EdgeSwipe.Edge) -> String {
        switch (edge, isEpisode) {
        case (.left, false): return "backward.end.fill"
        case (.right, false): return "forward.end.fill"
        case (.left, true): return "gobackward.15"
        case (.right, true): return "goforward.15"
        }
    }
}

extension Metrics {
    /// The circle that slides in from the edge while swiping.
    /// It fits inside the 48 pt side margin (4 + 40), so it never covers the cover art, not
    /// even for a moment (docs/06).
    enum EdgeSwipeIndicator {
        static let size: CGFloat = 40
        static let iconSize: CGFloat = 16
        /// Distance from the screen edge once the swipe is committed.
        static let inset: CGFloat = 4
    }
}

extension Palette {
    /// The indicator before the swipe is committed: white at 16 %.
    static let edgeSwipeIndicator = Color.white.opacity(0.16)
}
