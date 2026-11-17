import SwiftUI

// Spotify's guidelines ask that names cut with "…" can still be read whole, "with a marquee
// or a tap" (docs/06-cumplimiento.md, "Metadatos"; docs/02-diseno.md, "Reproducción").
//
// Nowdeck uses a marquee: the phone sits on a desk and is read at a glance, and most of the
// names that can be cut (origin, "Reproduciendo en …", the mini player) are already buttons,
// so a tap cannot also mean "show the whole name". Library cards are the exception: tapping
// plays them, and a long press shows the full name (`LibraryCard`).
//
// Behaviour:
// - A text that fits is drawn as is, without any motion.
// - A text that does not fit rests at its start for `MarqueeMotion.pause`, then scrolls left
//   until a copy of it (after `MarqueeMotion.gap`) takes its place, and starts over. The right
//   edge fades out, so the cut reads as "there is more".
// - With Reduce Motion on, it scrolls a single pass each time the text changes and then stays
//   at its start.
// - VoiceOver always reads the whole text.

/// The arithmetic of the marquee, separate from the view so it can be tested.
struct MarqueeMotion: Equatable {
    /// Space between the end of the text and the copy that follows it.
    static let gap: CGFloat = 48
    /// Scrolling speed in points per second: slow enough to read from a desk.
    static let speed: CGFloat = 30
    /// Rest at the start, before every pass.
    static let pause: TimeInterval = 3
    /// Width of the fade on the right edge while the text does not fit.
    static let fadeWidth: CGFloat = 24
    /// Layout rounding: a text this much wider than its room still counts as fitting.
    static let tolerance: CGFloat = 0.5

    /// Width of the text on a single line, without limits.
    var textWidth: CGFloat
    /// Width the layout gives the text.
    var availableWidth: CGFloat

    var needsScrolling: Bool {
        availableWidth > 0 && textWidth > availableWidth + Self.tolerance
    }

    /// One pass moves the text left by its own width plus the gap, which puts the copy
    /// exactly where the text started: resetting the offset afterwards is invisible.
    var distance: CGFloat {
        textWidth + Self.gap
    }

    var duration: TimeInterval {
        TimeInterval(distance / Self.speed)
    }

    /// Whether a text limited to some lines is cut, from its height with and without the
    /// limit.
    static func isCut(fullHeight: CGFloat, limitedHeight: CGFloat) -> Bool {
        fullHeight > limitedHeight + tolerance
    }
}

/// A single line of text that scrolls when it does not fit (see the notes above).
///
/// Style the text before passing it (`Text.font`, `foregroundColor`), or apply
/// `.textStyle(…)` and `.foregroundStyle(…)` to the marquee: both reach the text.
struct MarqueeText: View {
    let text: Text
    /// Restarts the motion from the start when it changes: pass the strings shown.
    let id: String
    /// What VoiceOver reads; the text itself by default.
    var accessibilityText: Text?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    init(_ text: Text, id: String, accessibilityText: Text? = nil) {
        self.text = text
        self.id = id
        self.accessibilityText = accessibilityText
    }

    /// A name from Spotify, shown verbatim (never localized nor read as Markdown).
    init(verbatim string: String) {
        self.init(Text(verbatim: string), id: string)
    }

    private var motion: MarqueeMotion {
        MarqueeMotion(textWidth: textWidth, availableWidth: availableWidth)
    }

    var body: some View {
        // The invisible text gives the size: as wide as the text, never wider than the room
        // offered, and one line high. What is drawn goes on top of it.
        text
            .lineLimit(1)
            .hidden()
            .background(WidthReader(width: $availableWidth))
            .background(alignment: .leading) {
                text
                    .fixedSize()
                    .hidden()
                    .background(WidthReader(width: $textWidth))
            }
            .overlay(alignment: .leading) {
                if motion.needsScrolling {
                    scrollingText
                } else {
                    text.lineLimit(1)
                }
            }
            .task(id: TaskKey(id: id, motion: motion, reduceMotion: reduceMotion)) {
                await run(motion)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText ?? text)
    }

    private var scrollingText: some View {
        HStack(spacing: MarqueeMotion.gap) {
            text
            text
        }
        .lineLimit(1)
        .fixedSize()
        .offset(x: offset)
        .frame(width: availableWidth, alignment: .leading)
        .clipped()
        .mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: MarqueeMotion.fadeWidth)
            }
        }
    }

    private func run(_ motion: MarqueeMotion) async {
        setOffset(0, animation: nil)
        guard motion.needsScrolling else { return }
        repeat {
            try? await Task.sleep(nanoseconds: UInt64(MarqueeMotion.pause * 1_000_000_000))
            if Task.isCancelled { return }
            setOffset(-motion.distance, animation: .linear(duration: motion.duration))
            try? await Task.sleep(nanoseconds: UInt64(motion.duration * 1_000_000_000))
            if Task.isCancelled { return }
            setOffset(0, animation: nil)
        } while !reduceMotion
    }

    private func setOffset(_ value: CGFloat, animation: Animation?) {
        var transaction = Transaction(animation: animation)
        transaction.disablesAnimations = animation == nil
        withTransaction(transaction) { offset = value }
    }

    private struct TaskKey: Equatable {
        var id: String
        var motion: MarqueeMotion
        var reduceMotion: Bool
    }
}

/// Text that wraps up to `lineLimit` lines and, if it still does not fit, becomes a
/// single-line marquee (the track title in the player, which takes up to two lines).
struct WrappingMarqueeText: View {
    let text: Text
    let id: String
    let lineLimit: Int

    @State private var fullHeight: CGFloat = 0
    @State private var limitedHeight: CGFloat = 0

    var body: some View {
        Group {
            if MarqueeMotion.isCut(fullHeight: fullHeight, limitedHeight: limitedHeight) {
                MarqueeText(text, id: id)
            } else {
                text
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Both versions are measured at the width the text gets, whichever is drawn.
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                text
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(HeightReader(height: $limitedHeight))
                text
                    .fixedSize(horizontal: false, vertical: true)
                    .background(HeightReader(height: $fullHeight))
            }
            .hidden()
        }
    }
}

// MARK: - Measuring

private struct WidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { width = $0 }
        }
    }
}

private struct HeightReader: View {
    @Binding var height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { height = proxy.size.height }
                .onChange(of: proxy.size.height) { height = $0 }
        }
    }
}
