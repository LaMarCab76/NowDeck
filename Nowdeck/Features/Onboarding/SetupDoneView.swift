import SwiftUI

/// Setup · "¡Listo!": the last moment of the setup, still in portrait.
///
/// The ring draws itself, the check follows, and the texts rise into place. Then `onFinish`
/// opens the player, which fades in while the screen rotates to landscape. With Reduce
/// Motion everything simply fades in.
struct SetupDoneView: View {
    let onFinish: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ringProgress: CGFloat = 0
    @State private var checkProgress: CGFloat = 0
    @State private var badgeScale: CGFloat = 0.6
    @State private var showsTexts = false

    /// Time on screen before the player opens.
    static let duration: TimeInterval = 1.8
    private static let badgeSize: CGFloat = 112

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            badge
            VStack(spacing: Spacing.s) {
                Text("¡Listo!")
                    .textStyle(.welcomeTitle)
                    .foregroundStyle(theme.palette.text.color)
                    .accessibilityAddTraits(.isHeader)
                Text("Nowdeck ya está conectado a tu Spotify. Girá el iPhone y apoyalo en el escritorio.")
                    .textStyle(.body)
                    .foregroundStyle(theme.palette.bodyText.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(showsTexts ? 1 : 0)
            .offset(y: showsTexts || reduceMotion ? 0 : 16)
            Spacer()
        }
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
        .task { await run() }
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(theme.palette.accent.color.opacity(Palette.activeToggleOpacity))
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(theme.palette.accent.color,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckmarkShape()
                .trim(from: 0, to: checkProgress)
                .stroke(theme.palette.accent.color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .frame(width: Self.badgeSize * 0.42, height: Self.badgeSize * 0.32)
        }
        .frame(width: Self.badgeSize, height: Self.badgeSize)
        .scaleEffect(badgeScale)
        .accessibilityHidden(true)
    }

    private func run() async {
        if reduceMotion {
            ringProgress = 1
            checkProgress = 1
            badgeScale = 1
            withAnimation(.easeOut(duration: 0.3)) { showsTexts = true }
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { badgeScale = 1 }
            withAnimation(.easeInOut(duration: 0.5)) { ringProgress = 1 }
            withAnimation(.easeOut(duration: 0.3).delay(0.45)) { checkProgress = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(0.6)) { showsTexts = true }
        }
        UIAccessibility.post(notification: .announcement,
                             argument: String(localized: "Listo. Nowdeck ya está conectado."))
        try? await Task.sleep(nanoseconds: UInt64(Self.duration * 1_000_000_000))
        guard !Task.isCancelled else { return }
        onFinish()
    }
}

/// A check mark drawn as one stroke, so it can be revealed with `trim`.
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
