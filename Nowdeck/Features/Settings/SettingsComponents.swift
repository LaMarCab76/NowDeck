import SwiftUI

/// "TEMA", "COLOR DE RESALTADO"…: uppercase monospaced label over its controls (gap 8).
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .textStyle(.label)
                .foregroundStyle(theme.palette.label.color)
                .accessibilityAddTraits(.isHeader)
                .fadesDuringBackgroundPreview()
            content
        }
    }
}

/// Lays out children in rows and wraps when a row is full (CSS `flex-wrap`), for the theme
/// chips. `Layout` is available from iOS 16.
struct FlowLayout: Layout {
    var spacing: CGFloat = Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// A theme chip: 40 high, accent sample on the theme's background, name.
struct ThemeChip: View {
    let name: Text
    let accent: RGBColor
    let background: RGBColor
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                // 18 pt accent dot, 3 pt ring of the theme's background, 1 pt light outline
                // (CSS box-shadow 0 0 0 3px fondo, 0 0 0 4px white 30 %).
                Circle()
                    .fill(accent.color)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(background.color).frame(width: 24, height: 24))
                    .background(Circle().fill(Palette.chipSwatchRing).frame(width: 26, height: 26))
                    .accessibilityHidden(true)
                name
                    .textStyle(.pill)
                    .lineLimit(1)
            }
            .foregroundStyle(theme.palette.text.color)
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(minHeight: 40)
            .background(Capsule().fill(isSelected ? Palette.chipSelectedFill : .clear))
            .overlay(
                Capsule().strokeBorder(isSelected ? theme.palette.accent.color : Palette.chipUnselectedBorder,
                                       lineWidth: 1.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A 32 pt color circle in a 44 pt tap area. The selected one gets a 2 pt ring in `texto`,
/// 3 pt away from the circle (CSS box-shadow 0 0 0 3px fondo, 0 0 0 5px texto).
struct AccentSwatch: View {
    let choice: AccentChoice
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(choice.color.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(theme.palette.text.color, lineWidth: 2)
                        .frame(width: 40, height: 40)
                        .opacity(isSelected ? 1 : 0)
                )
                .frame(width: Metrics.minTouchTarget, height: Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(choice.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Segmented control of the mockups: track of 44 (padding 4, white 8 %), options of 36 with
/// radius 18; the selected one is filled with `texto` and its text in `fondo`.
struct SettingsSegmentedControl<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: LocalizedStringKey
        var id: Value { value }
    }

    let options: [Option]
    /// `nil` highlights nothing (a solid background that is neither black nor dark gray).
    let selection: Value?
    let onSelect: @MainActor (Value) -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button { onSelect(option.value) } label: {
                    Text(option.title)
                        .textStyle(.pill)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? theme.palette.background.color
                                                    : theme.palette.text.color)
                        .padding(.horizontal, Spacing.m)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(isSelected ? theme.palette.text.color : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(Spacing.xxs)
        .background(Capsule().fill(Palette.segmentTrack))
        // Never truncate an option: the row around it gives way instead.
        .fixedSize()
    }
}

/// The switch of the mockup: track 56×32 (accent when on), knob 26 in `texto`, in a 44 pt
/// high tap area.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSwitch(configuration: configuration)
    }

    private struct SettingsSwitch: View {
        let configuration: ToggleStyleConfiguration
        @EnvironmentObject private var theme: ThemeStore

        var body: some View {
            HStack(spacing: Spacing.l) {
                configuration.label
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { configuration.isOn.toggle() }
                } label: {
                    ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(configuration.isOn ? theme.palette.accent.color : Palette.switchTrackOff)
                            .frame(width: 56, height: 32)
                        Circle()
                            .fill(theme.palette.text.color)
                            .frame(width: 26, height: 26)
                            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                            .padding(.horizontal, 3)
                    }
                    .frame(width: 56, height: Metrics.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The whole row is the accessible switch (below); the button is its visual part.
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? Text("Activado") : Text("Desactivado"))
            .accessibilityAction { configuration.isOn.toggle() }
        }
    }
}

/// "Exportar tema" / "Importar tema": outlined capsule of 48 with an 18 pt icon.
struct SettingsOutlineLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(title)
                .textStyle(.pill)
                .lineLimit(1)
        }
        .foregroundStyle(theme.palette.text.color)
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
        .overlay(Capsule().strokeBorder(Palette.settingsButtonBorder, lineWidth: 1.5))
        .contentShape(Capsule())
    }
}
