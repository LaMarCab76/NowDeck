import SwiftUI
import UniformTypeIdentifiers

/// Ajustes (Ajustes.dc.html): a 200 pt column with "Volver", the title and two vertical tabs,
/// and the selected section on the right.
///
/// It is self-contained: the player presents it full screen (for example with
/// `.fullScreenCover`), and "Volver" dismisses it. It needs `ThemeStore` and
/// `ThemeImportCoordinator` in the environment.
struct SettingsView: View {
    enum Section: Hashable {
        case appearance
        case player
    }

    @State private var section: Section
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeStore

    init(section: Section = .appearance) {
        _section = State(initialValue: section)
    }

    /// Mockup: padding 28 (top and bottom) and 48 (sides).
    private let margins = ScreenMargins(top: 28, horizontal: 48, bottom: 28)

    var body: some View {
        // The outer reader measures the safe area; the content then ignores it and applies
        // the larger of the mockup margin and the safe area on each side.
        GeometryReader { proxy in
            let insets = margins.insets(for: proxy.safeAreaInsets)
            HStack(alignment: .top, spacing: 40) {
                sidebar
                    .frame(width: 200, alignment: .leading)
                    .padding(.bottom, insets.bottom)

                // The sections scroll when they do not fit (narrow screens, large Dynamic
                // Type). Their bottom margin goes inside the scroll view, so content scrolls
                // to the screen edge instead of being cut 28 pt above it.
                Group {
                    switch section {
                    case .appearance: AppearanceSettingsView(bottomMargin: insets.bottom)
                    case .player: PlayerSettingsView(bottomMargin: insets.bottom)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(EdgeInsets(top: insets.top, leading: insets.leading, bottom: 0,
                                trailing: insets.trailing))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
        }
        .foregroundStyle(theme.palette.text.color)
        .background(theme.palette.background.color.ignoresSafeArea())
        .orientationLock(.landscape)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .themeImportPresenter()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Volver")
                        .textStyle(.pill)
                }
                .frame(minHeight: Metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("Ajustes")
                .textStyle(.screenTitle)
                .tracking(-0.02 * 34)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                tab("Apariencia", .appearance)
                tab("Reproductor", .player)
            }
        }
    }

    private func tab(_ title: LocalizedStringKey, _ value: Section) -> some View {
        let isSelected = section == value
        return Button { section = value } label: {
            Text(title)
                .textStyle(.settingsTab)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Metrics.minTouchTarget, alignment: .leading)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .fill(isSelected ? Palette.settingsTabSelected : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isHeader] : [])
    }
}

/// A column that scrolls only when its content does not fit (large Dynamic Type), and
/// otherwise fills the height so a bottom row can stick to the bottom (CSS `margin-top: auto`).
struct SettingsColumn<Content: View>: View {
    var spacing: CGFloat
    var bottomMargin: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .padding(.top, 10)
                .padding(.bottom, bottomMargin)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Apariencia

struct AppearanceSettingsView: View {
    var bottomMargin: CGFloat = 28
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var importer: ThemeImportCoordinator
    @State private var isPickingFile = false

    var body: some View {
        SettingsColumn(spacing: 18, bottomMargin: bottomMargin) {
            SettingsSection(title: "TEMA") {
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(theme.presets) { preset in
                        ThemeChip(name: Text(verbatim: preset.theme.name),
                                  accent: RGBColor(hex: preset.theme.colors?.accent ?? "") ?? .white,
                                  background: RGBColor(hex: preset.theme.colors?.background ?? "") ?? .black,
                                  isSelected: theme.selectedPreset?.id == preset.id) {
                            theme.selectPreset(preset)
                        }
                    }
                    customChip
                }
            }

            SettingsSection(title: "COLOR DE RESALTADO") {
                HStack(spacing: Spacing.xxs) {
                    ForEach(AccentChoice.all) { choice in
                        AccentSwatch(choice: choice, isSelected: choice.color == theme.accent) {
                            theme.setAccent(choice.color)
                        }
                    }
                }
                // The 44 pt tap areas are wider than the 32 pt circles: align the first circle
                // with the label, as in the mockup.
                .padding(.leading, -6)
            }

            SettingsSection(title: "FONDO DEL REPRODUCTOR") {
                SettingsSegmentedControl(
                    options: [
                        .init(value: PlayerBackgroundOption.black, title: "Negro"),
                        .init(value: .darkGray, title: "Gris oscuro"),
                        .init(value: .artwork, title: "Según la carátula"),
                    ],
                    selection: theme.backgroundOption,
                    onSelect: { theme.setBackgroundOption($0) }
                )
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                ShareLink(item: theme.export,
                          preview: SharePreview(Text(verbatim: ThemeFile.fileName(for: theme.theme)))) {
                    SettingsOutlineLabel(title: "Exportar tema", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        isPickingFile = true
                    } label: {
                        Label("Elegir un archivo", systemImage: "folder")
                    }
                    Button {
                        importer.importFromClipboard()
                    } label: {
                        Label("Pegar desde el portapapeles", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    SettingsOutlineLabel(title: "Importar tema", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
            }
        }
        .fileImporter(isPresented: $isPickingFile,
                      allowedContentTypes: [.nowdeckTheme, .json]) { result in
            importer.importFile(result)
        }
    }

    /// "Personalizado": the last imported or edited theme. Before there is one, it shows the
    /// mockup's neutral sample and does nothing.
    private var customChip: some View {
        let custom = theme.selectedPreset == nil ? theme.theme : theme.customTheme
        let colors = custom.flatMap { ThemeColorSet($0.colors) }
        return ThemeChip(name: Text("Personalizado"),
                         accent: colors?.accent ?? RGBColor(hex: "#F2EEE8")!,
                         background: colors?.background ?? .black,
                         isSelected: theme.selectedPreset == nil) {
            theme.selectCustom()
        }
        .disabled(custom == nil)
    }
}

// MARK: - Reproductor

struct PlayerSettingsView: View {
    var bottomMargin: CGFloat = 28
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        SettingsColumn(spacing: Spacing.m, bottomMargin: bottomMargin) {
            Text("LETRAS")
                .textStyle(.label)
                .foregroundStyle(theme.palette.label.color)
                .accessibilityAddTraits(.isHeader)

            Toggle(isOn: Binding(get: { theme.showsLyricsButton },
                                 set: { theme.setShowsLyricsButton($0) })) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Mostrar letras")
                        .textStyle(.settingsRowTitle)
                    Text("Suma un botón de letras al reproductor.")
                        .textStyle(.helper)
                        .foregroundStyle(theme.palette.bodyText.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(SettingsSwitchStyle())
            .padding(.vertical, Spacing.m)
            .padding(.horizontal, Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.settingsCard)
            )

            HStack(spacing: Spacing.l) {
                Text("Ancho de las letras")
                    .textStyle(.settingsOptionTitle)
                Spacer(minLength: 0)
                SettingsSegmentedControl(
                    options: [
                        .init(value: Theme.LyricsWidth.half, title: "Mitad"),
                        .init(value: .twoThirds, title: "2/3"),
                        .init(value: .full, title: "Completo"),
                    ],
                    selection: theme.lyricsWidth,
                    onSelect: { theme.setLyricsWidth($0) }
                )
            }
            .padding(.horizontal, Spacing.xxs)

            Text("Las letras vienen de LRCLIB, una base comunitaria: no las provee Spotify y pueden faltar o tener errores. Con sincronía por palabra se resaltan mientras suenan; si no, se ve la estrofa completa.")
                .textStyle(.settingsNote)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.xxs)
        }
    }
}
