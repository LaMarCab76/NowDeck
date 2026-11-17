import SwiftUI

/// Importar tema (TemaImportar.dc.html): a sheet of 800×398 on the black background, with
/// the file's JSON on the left and the validation result, preview, warnings and actions on
/// the right.
///
/// It is shown as a full-screen cover drawing its own sheet, because a system sheet in
/// landscape on iPhone cannot have the mockup's size and margins.
struct ThemeImportView: View {
    let request: ThemeImportRequest
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var coordinator: ThemeImportCoordinator
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            // docs/02: 800 wide on 896 (48 pt on each side); narrower screens (8 Plus, 736)
            // keep the 48 pt margins and get a 240 pt right column.
            let width = min(800, proxy.size.width - 96)
            let sideWidth: CGFloat = width >= 760 ? 280 : 240

            sheet(sideWidth: sideWidth)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .padding(.top, 16)
                .offset(y: dragOffset)
                .frame(maxWidth: .infinity)
        }
        // The mockup measures from the screen edges; the status bar and home indicator are
        // hidden, and the sheet's own padding keeps the content clear of the corners.
        .ignoresSafeArea()
        .background(theme.palette.background.color.ignoresSafeArea())
        .foregroundStyle(theme.palette.text.color)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func sheet(sideWidth: CGFloat) -> some View {
        VStack(spacing: Spacing.xs) {
            handle
            header
            HStack(alignment: .top, spacing: Spacing.l) {
                codeBox
                sideColumn
                    .frame(width: sideWidth)
            }
            .padding(.bottom, Spacing.m)
        }
        .padding(.top, 10)
        .padding(.horizontal, 24)
        .background(
            UnevenTopRoundedRectangle(radius: Radius.sheet)
                .fill(theme.palette.surface.color)
        )
    }

    // MARK: Header

    private var handle: some View {
        Capsule()
            .fill(Palette.sheetHandle)
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity, minHeight: 5)
            .contentShape(Rectangle().inset(by: -12))
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = max(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height > 80 {
                            coordinator.dismiss()
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                        }
                    }
            )
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("Importar tema")
                    .textStyle(.importTitle)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: request.sourceName)
                    .textStyle(.importFileName)
                    .foregroundStyle(theme.palette.label.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button { coordinator.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: Metrics.minTouchTarget, height: Metrics.minTouchTarget)
                    .background(Circle().fill(Palette.closeButtonFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Cerrar"))
        }
        .frame(minHeight: Metrics.minTouchTarget)
    }

    // MARK: Left: the file

    private var codeBox: some View {
        // Vertical scroll only, with the lines wrapped at the box's width: JSON pasted on a
        // single line would otherwise run off the right edge and hide most of the file.
        ScrollView(.vertical) {
            // `verbatim`: the text comes from the file and must never be read as Markdown or
            // as a localization key.
            Text(verbatim: request.contents.isEmpty ? " " : request.contents)
                .textStyle(.importCode)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.vertical, 14)
                .padding(.horizontal, Spacing.m)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(Palette.codeBackground.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(Palette.codeBorder.color, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .accessibilityLabel(Text("Contenido del archivo"))
    }

    // MARK: Right: result and actions

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch request.result {
            case .success(let validated):
                // Takes all the height above the buttons (no spacer: a spacer would split
                // that height with the list and cut a warning in half halfway down). What
                // does not fit scrolls and fades out at the bottom edge.
                FadingScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        status(Text("Tema válido"), systemImage: "checkmark.circle",
                               color: theme.palette.accent.color)
                        ThemePreviewCard(theme: validated.theme)
                        ForEach(Array(validated.warnings.enumerated()), id: \.offset) { _, warning in
                            message(Text(warning.message))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: Spacing.xs) {
                    Button {
                        theme.apply(validated)
                        coordinator.dismiss()
                    } label: {
                        Text("Aplicar tema")
                            .textStyle(.importApply)
                            .foregroundStyle(theme.palette.textOnAccent.color)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Capsule().fill(theme.palette.accent.color))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    cancelButton
                }

            case .failure(let error):
                status(Text("No se puede importar"), systemImage: "xmark.circle",
                       color: theme.palette.warning.color)
                message(Text(error.message), icon: false)
                Spacer(minLength: 0)
                cancelButton
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var cancelButton: some View {
        Button { coordinator.dismiss() } label: {
            Text("Cancelar")
                .textStyle(.pill)
                .frame(maxWidth: .infinity, minHeight: Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func status(_ title: Text, systemImage: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .accessibilityHidden(true)
            title
                .textStyle(.importStatus)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    /// A warning (yellow triangle) or, with `icon: false`, the detail of an error.
    private func message(_ text: Text, icon: Bool = true) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            if icon {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.palette.warning.color)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
            }
            text
                .textStyle(.importMessage)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A vertical scroll view whose bottom edge fades out while there is more content below,
/// with a small arrow pointing down, so a row cut by the edge reads as "there is more"
/// instead of a broken layout. The content gets the fade's height as extra bottom space,
/// so the last row can scroll fully clear of the fade.
struct FadingScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    static var fadeHeight: CGFloat { 32 }
    private static var space: String { "FadingScrollView" }

    @EnvironmentObject private var theme: ThemeStore
    @State private var contentHeight: CGFloat = 0
    /// Bottom of the content, in the scroll view's own coordinates (moves as it scrolls).
    @State private var contentBottom: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var overflows: Bool {
        contentHeight > viewportHeight + 0.5
    }

    /// Some content is still hidden below the bottom edge.
    private var hasMoreBelow: Bool {
        overflows && contentBottom > viewportHeight + 0.5
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content
                .background(GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(Self.space))
                    Color.clear
                        .onAppear {
                            contentHeight = frame.height
                            contentBottom = frame.maxY
                        }
                        .onChange(of: frame) { frame in
                            contentHeight = frame.height
                            contentBottom = frame.maxY
                        }
                })
                .padding(.bottom, overflows ? Self.fadeHeight : 0)
        }
        .coordinateSpace(name: Self.space)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { viewportHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { viewportHeight = $0 }
        })
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                if hasMoreBelow {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fadeHeight)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if hasMoreBelow {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.palette.label.color)
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hasMoreBelow)
    }
}

/// The preview of an imported theme, with its own colors (merged with the default for the
/// ones it does not define): background, an artwork placeholder in `superficie`, the name in
/// `texto`, "Vista previa" in `textoSecundario` and a dot in `acento`.
struct ThemePreviewCard: View {
    let theme: Theme

    var body: some View {
        let colors = ThemeColorSet(theme.mergedWithDefault().colors) ?? ThemeColorSet(Theme.default.colors)!
        HStack(spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous)
                .fill(colors.surface.color)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: theme.name)
                    .textStyle(.importPreviewTitle)
                    .foregroundStyle(colors.text.color)
                    .lineLimit(1)
                Text("Vista previa")
                    .textStyle(.importPreviewSubtitle)
                    .foregroundStyle(colors.secondaryText.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle()
                .fill(colors.accent.color)
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(colors.background.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(colors.surface.color, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

/// A rectangle with only the top corners rounded (sheets). `UnevenRoundedRectangle` is
/// iOS 17+, so it is drawn by hand.
struct UnevenTopRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
