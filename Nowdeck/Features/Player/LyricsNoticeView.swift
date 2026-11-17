import SwiftUI

/// The light pill shown for 3 s when a track has no lyrics (`Main.dc.html`, `avisoVisible`).
///
/// The player places it at the top of the screen, centered, `Metrics.Notice.top` from the
/// edge, above everything else:
///
/// ```swift
/// .overlay(alignment: .top) {
///     if let notice = lyrics.notice {
///         LyricsNoticeView(notice: notice).padding(.top, Metrics.Notice.top)
///     }
/// }
/// ```
struct LyricsNoticeView: View {
    let notice: LyricsModeController.Notice
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: Metrics.Notice.iconSpacing) {
            NoLyricsIcon()
                .stroke(style: StrokeStyle(lineWidth: Metrics.iconStroke, lineCap: .round, lineJoin: .round))
                .frame(width: Metrics.Notice.iconSize, height: Metrics.Notice.iconSize)
                .accessibilityHidden(true)
            Text(message)
                .textStyle(.notice)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Palette.noticeForeground)
        .padding(.leading, Metrics.Notice.leadingPadding)
        .padding(.trailing, Metrics.Notice.trailingPadding)
        .frame(height: Metrics.Notice.height)
        .background(Capsule().fill(theme.palette.text.color))
        .shadow(color: Palette.noticeShadow, radius: Metrics.Notice.shadowRadius, y: Metrics.Notice.shadowY)
        .accessibilityElement(children: .combine)
        // Announced as a status message (docs/02-diseno.md, "Aviso"), again if it changes
        // while on screen.
        .onAppear { AccessibilityAnnouncement.post(message) }
        .onChange(of: notice) { _ in AccessibilityAnnouncement.post(message) }
    }

    private var message: LocalizedStringResource {
        switch notice {
        case .notFound: return "No encontramos la letra de este tema"
        case .failed: return "No pudimos buscar la letra. Probá de nuevo en un rato."
        }
    }
}

/// Speech bubble with a slash, drawn from the mockup's 24×24 SVG
/// (`M4 5h16v11H9l-5 4V5z` and `M3 3l18 18`). SF Symbols has no crossed-out bubble.
private struct NoLyricsIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(4, 5))
        path.addLine(to: point(20, 5))
        path.addLine(to: point(20, 16))
        path.addLine(to: point(9, 16))
        path.addLine(to: point(4, 20))
        path.closeSubpath()
        path.move(to: point(3, 3))
        path.addLine(to: point(21, 21))
        return path
    }
}
