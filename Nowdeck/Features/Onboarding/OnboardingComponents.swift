import SwiftUI

/// Layout shared by the three portrait onboarding screens.
///
/// The mockups are 414×896 with `justify-content: space-between`: `top` sticks to the top,
/// `footer` to the bottom and `middle` (optional) floats between them. When the content does
/// not fit (iPhone 8 Plus, large Dynamic Type, keyboard open) the screen scrolls instead of
/// clipping.
struct OnboardingScreen<Top: View, Middle: View, Footer: View>: View {
    /// 72 on the welcome screen, 60 on the steps (measured from the top of the screen, as in
    /// the mockups, which include the status bar area).
    var topPadding: CGFloat
    @ViewBuilder var top: Top
    @ViewBuilder var middle: Middle
    @ViewBuilder var footer: Footer

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    top
                    Spacer(minLength: Spacing.xl)
                    middle
                    Spacer(minLength: Spacing.xl)
                    footer
                }
                .padding(.top, topPadding)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Only the container area: the keyboard still pushes the content up.
        .ignoresSafeArea(.container, edges: .vertical)
    }
}

extension OnboardingScreen where Middle == EmptyView {
    init(topPadding: CGFloat, @ViewBuilder top: () -> Top, @ViewBuilder footer: () -> Footer) {
        self.init(topPadding: topPadding, top: top, middle: { EmptyView() }, footer: footer)
    }
}

/// "‹ Atrás" on the left and "PASO 1 DE 2" on the right.
struct OnboardingStepHeader: View {
    let stepLabel: LocalizedStringKey
    let onBack: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Atrás")
                        .textStyle(.backButton)
                }
                .frame(minHeight: Metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.palette.text.color)

            Spacer()

            Text(stepLabel)
                .textStyle(.label)
                .foregroundStyle(theme.palette.label.color)
        }
    }
}

/// A line of a check list ("VAS A NECESITAR", permissions).
struct OnboardingCheckItem: View {
    let text: LocalizedStringKey
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.palette.accent.color)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .textStyle(.listItem)
                .foregroundStyle(theme.palette.text.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A titled check list.
struct OnboardingCheckList<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .textStyle(.label)
                .foregroundStyle(theme.palette.label.color)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// Provisional Nowdeck logo: a landscape rectangle (the phone on its side) with an accent
/// square (the artwork) and a line (the text). Drawn from the 28×28 SVG of the mockup.
struct NowdeckLogo: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .stroke(theme.palette.text.color, lineWidth: 2)
                .frame(width: 24, height: 14)
                .offset(x: 2, y: 7)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(theme.palette.accent.color)
                .frame(width: 6, height: 6)
                .offset(x: 6, y: 11)
            Capsule()
                .fill(theme.palette.text.color)
                .frame(width: 9, height: 2)
                .offset(x: 14, y: 15)
        }
        .frame(width: 28, height: 28, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// The "deck" illustration of the welcome screen (200×110 SVG of the mockup).
struct DeckIllustration: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Phone body.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RGBColor(hex: "#161616")!.color)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Palette.hairline.color, lineWidth: 2)
                )
                .frame(width: 192, height: 92)
                .offset(x: 4, y: 4)
            // Artwork.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(theme.palette.accent.color)
                .frame(width: 52, height: 52)
                .offset(x: 18, y: 18)
            // Title and artist.
            Capsule().fill(theme.palette.text.color)
                .frame(width: 80, height: 10)
                .offset(x: 84, y: 24)
            Capsule().fill(Palette.outline.color)
                .frame(width: 52, height: 8)
                .offset(x: 84, y: 42)
            // Progress bar.
            Capsule().fill(Palette.hairline.color)
                .frame(width: 164, height: 4)
                .offset(x: 18, y: 80)
            Capsule().fill(theme.palette.text.color)
                .frame(width: 64, height: 4)
                .offset(x: 18, y: 80)
            // Stand.
            Capsule().fill(Palette.hairline.color)
                .frame(width: 86, height: 6)
                .offset(x: 57, y: 97)
        }
        .frame(width: 200, height: 110, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
