import SwiftUI
import UniformTypeIdentifiers

/// Ajustes (Ajustes.dc.html): a 200 pt column with "Volver", the title and two vertical tabs,
/// and the selected section on the right.
///
/// It is self-contained: the player presents it full screen (for example with
/// `.fullScreenCover`), and "Volver" dismisses it. It needs `ThemeStore` and
/// `ThemeImportCoordinator` in the environment. The player model, when given, supplies the
/// sample photo of the background preview (`BackgroundPreviewModel`).
struct SettingsView: View {
    enum Section: Hashable {
        case appearance
        case player
    }

    @State private var section: Section
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeStore
    @StateObject private var preview: BackgroundPreviewModel

    init(section: Section = .appearance, player: PlayerModel? = nil) {
        _section = State(initialValue: section)
        _preview = StateObject(wrappedValue: BackgroundPreviewModel(player: player))
    }

    /// Mockup: padding 28 (top and bottom) and 48 (sides).
    private let margins = SettingsMargins(top: 28, horizontal: 48, bottom: 28)

    var body: some View {
        // The outer reader measures the safe area; the content then ignores it and applies
        // the larger of the mockup margin and the safe area on each side.
        GeometryReader { proxy in
            let insets = margins.insets(for: proxy.safeAreaInsets)
            HStack(alignment: .top, spacing: 40) {
                sidebar
                    .frame(width: 200, alignment: .leading)
                    .padding(.bottom, insets.bottom)
                    .fadesDuringBackgroundPreview()

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
        .environment(\.backgroundPreview, preview)
        .environment(\.backgroundPreviewEditing, preview.editing)
        .background(background.ignoresSafeArea())
        .overlay(alignment: .topLeading) { previewAttribution }
        .onDisappear { preview.cancel() }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .themeImportPresenter()
    }

    /// The theme's background and, while the finger is on a background slider, the preview
    /// of the player's background over it.
    private var background: some View {
        ZStack {
            theme.palette.background.color
            if preview.editing != nil {
                PlayerBackgroundView(color: theme.palette.background.color,
                                     artistImage: preview.image,
                                     blur: preview.blur, dim: preview.dim)
                    .transition(.opacity)
            }
        }
        .animation(Motion.backgroundPreview, value: preview.editing != nil)
    }

    /// The artist's photo is Spotify content: while it shows, the Spotify icon sits where the
    /// player has it, top left, and opens that artist in Spotify (docs/06).
    @ViewBuilder
    private var previewAttribution: some View {
        // Only with a photo: without one the preview is just the theme's color.
        if preview.editing != nil, preview.image != nil, preview.artistURL != nil {
            GeometryReader { proxy in
                let insets = margins.insets(for: proxy.safeAreaInsets)
                // Measured from the physical edges, like the player's top row.
                SpotifyLogoLink(url: preview.artistURL, variant: .icon)
                    .padding(.leading, insets.leading)
                    .padding(.top, Spacing.Player.top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea()
            }
            .transition(.opacity)
        }
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
    @Environment(\.backgroundPreviewEditing) private var previewEditing

    /// A scroll view clips its content to its bounds, and some controls draw a bit past the
    /// column's edge (the selected accent swatch's ring, 5 pt to the left). The scroll view
    /// is this much wider on each side and its content inset by the same amount, so nothing
    /// moves but the ring is not cut. `scrollClipDisabled()` would do it, but needs iOS 17.
    private let clipBleed: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .padding(.top, 10)
                .padding(.bottom, bottomMargin)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                .padding(.horizontal, clipBleed)
            }
            .padding(.horizontal, -clipBleed)
            .hidesScrollEdgeEffect(previewEditing != nil)
        }
    }
}

private extension View {
    /// iOS 26 darkens and blurs the edges of a scroll view. Over the background preview that
    /// shows as a dark band on the photo, so it is hidden while the preview shows.
    @ViewBuilder
    func hidesScrollEdgeEffect(_ hidden: Bool) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(hidden, for: .all)
        } else {
            self
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
            themeSection
                .fadesDuringBackgroundPreview()

            accentSection
                .fadesDuringBackgroundPreview()

            backgroundSection

            Spacer(minLength: 0)

            themeFileButtons
                .fadesDuringBackgroundPreview()
        }
        .fileImporter(isPresented: $isPickingFile,
                      allowedContentTypes: [.nowdeckTheme, .json]) { result in
            importer.importFile(result)
        }
    }

    private var themeSection: some View {
        SettingsSection(title: "TEMA") {
            FlowLayout(spacing: Spacing.xs) {
                ForEach(theme.presets) { preset in
                    ThemeChip(name: presetName(preset),
                              accent: RGBColor(hex: preset.theme.colors?.accent ?? "") ?? .white,
                              background: RGBColor(hex: preset.theme.colors?.background ?? "") ?? .black,
                              isSelected: theme.selectedPreset?.id == preset.id) {
                        theme.selectPreset(preset)
                    }
                }
                customChip
            }
        }
    }

    /// The chip label of a built-in theme, in the UI language. The `nombre` inside the
    /// bundled file stays in Spanish: it is theme data (exported files keep it), so the
    /// translation is looked up by the preset's file name instead.
    private func presetName(_ preset: ThemePreset) -> Text {
        switch preset.id {
        case "negro-y-verde": return Text("Negro y verde")
        case "ambar": return Text("Ámbar")
        case "azul-noche": return Text("Azul noche")
        default: return Text(verbatim: preset.theme.name)
        }
    }

    private var accentSection: some View {
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
    }

    /// While a slider is under the finger, only that slider stays (`BackgroundPreviewModel`).
    private var backgroundSection: some View {
        SettingsSection(title: "FONDO DEL REPRODUCTOR") {
            // Four options do not fit the iPhone 8 Plus column (400 pt) with the full
            // names: there the shorter ones are used.
            ViewThatFits(in: .horizontal) {
                backgroundControl(short: false)
                backgroundControl(short: true)
            }
            .fadesDuringBackgroundPreview()

            if theme.backgroundOption == .artistPhoto {
                ArtistPhotoSliders()
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private var themeFileButtons: some View {
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

    private func backgroundControl(short: Bool) -> some View {
        SettingsSegmentedControl(
            options: [
                .init(value: PlayerBackgroundOption.black, title: "Negro"),
                .init(value: .darkGray, title: short ? "Gris" : "Gris oscuro"),
                .init(value: .artwork, title: short ? "Carátula" : "Según la carátula"),
                .init(value: .artistPhoto, title: short ? "Artista" : "Foto del artista"),
            ],
            selection: theme.backgroundOption,
            onSelect: { theme.setBackgroundOption($0) }
        )
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

/// "Desenfoque" and "Oscurecer" of the artist's photo, shown only with "Foto del artista".
struct ArtistPhotoSliders: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.backgroundPreview) private var preview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            BackgroundSliderRow(control: .blur, title: "Desenfoque", value: theme.backgroundBlur,
                                onCommit: { theme.setBackgroundBlur($0) })
            BackgroundSliderRow(control: .dim, title: "Oscurecer", value: theme.backgroundDim,
                                onCommit: { theme.setBackgroundDim($0) })
            Text("Suavizan y oscurecen la foto del artista para que el título se lea mejor. Mientras movés uno, ves cómo queda.")
                .textStyle(.helper)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.xxs)
                .fadesDuringBackgroundPreview()
        }
        // The sample photo starts loading now, so it is usually there before the finger is.
        .onAppear { preview?.prepare() }
    }
}

/// One background slider, 0 to 100 % in steps of 5. The theme is saved when the finger lifts,
/// not on every step of the drag. While the finger is on it, the rest of Ajustes fades out
/// and the preview shows the value being chosen (`BackgroundPreviewModel`).
struct BackgroundSliderRow: View {
    var control: BackgroundPreviewModel.Control
    var title: LocalizedStringKey
    var value: Int
    var onCommit: (Int) -> Void

    @State private var draft: Double?
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.backgroundPreview) private var preview

    private var shown: Int { draft.map { Int($0) } ?? value }

    var body: some View {
        HStack(spacing: Spacing.l) {
            Text(title)
                .textStyle(.settingsOptionTitle)
                .frame(minWidth: 100, alignment: .leading)
            Slider(
                value: Binding(get: { draft ?? Double(value) }, set: { newValue in
                    draft = newValue
                    preview?.update(control, to: Int(newValue))
                }),
                in: 0...100,
                step: 5
            ) { editing in
                if editing {
                    preview?.begin(control, blur: theme.backgroundBlur, dim: theme.backgroundDim)
                    preview?.update(control, to: shown)
                    return
                }
                preview?.end()
                guard let draft else { return }
                onCommit(Int(draft))
                self.draft = nil
            }
            .tint(theme.palette.accent.color)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(verbatim: "\(shown) %"))
            Text(verbatim: "\(shown) %")
                .textStyle(.settingsOptionTitle)
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.xxs)
        .fadesDuringBackgroundPreview(keeps: control)
    }
}

// MARK: - Reproductor

struct PlayerSettingsView: View {
    var bottomMargin: CGFloat = 28
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        SettingsColumn(spacing: Spacing.m, bottomMargin: bottomMargin) {
            Text("PROGRESO")
                .textStyle(.label)
                .foregroundStyle(theme.palette.label.color)
                .accessibilityAddTraits(.isHeader)

            Toggle(isOn: $preferences.showsRemainingTime) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Mostrar tiempo restante")
                        .textStyle(.settingsRowTitle)
                    Text("A la derecha de la barra se ve cuánto falta, en vez de la duración del tema. También podés cambiarlo tocando ese tiempo en el reproductor.")
                        .textStyle(.helper)
                        .foregroundStyle(theme.palette.bodyText.color)
                        .fixedSize(horizontal: false, vertical: true)
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

            Text("LETRAS")
                .textStyle(.label)
                .foregroundStyle(theme.palette.label.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Spacing.s)

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

            HStack(spacing: Spacing.l) {
                Text("Estilo de las letras")
                    .textStyle(.settingsOptionTitle)
                Spacer(minLength: 0)
                SettingsSegmentedControl(
                    options: [
                        .init(value: LyricsStyle.byWord, title: "Por palabra"),
                        .init(value: .stanza, title: "Estrofa"),
                    ],
                    selection: preferences.lyricsStyle,
                    onSelect: { preferences.lyricsStyle = $0 }
                )
            }
            .padding(.horizontal, Spacing.xxs)

            LyricsOffsetRow(offsetMs: $preferences.lyricsOffsetMs)
                .padding(.horizontal, Spacing.xxs)

            Text("Las letras vienen de LRCLIB, una base comunitaria: no las provee Spotify y pueden faltar o tener errores. Con “Por palabra” se resaltan mientras suenan, si la letra tiene sincronía por palabra; si no, o con “Estrofa”, se ve la estrofa completa.")
                .textStyle(.settingsNote)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.xxs)

            Text("BIBLIOTECA")
                .textStyle(.label)
                .foregroundStyle(theme.palette.label.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Spacing.s)

            Toggle(isOn: $preferences.usesPlaylistFolders) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Carpetas de playlists (experimental)")
                        .textStyle(.settingsRowTitle)
                    Text("Lee tus carpetas con el servicio interno de Spotify, que no está aprobado para apps de terceros. Puede dejar de andar, y Spotify podría bloquear el Client ID de tu app.")
                        .textStyle(.helper)
                        .foregroundStyle(theme.palette.bodyText.color)
                        .fixedSize(horizontal: false, vertical: true)
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
        }
    }
}

/// "Sincronía de las letras": − and + move the lyrics 0.1 s later or earlier, to make up for
/// the delay between Spotify's position and what is heard (Bluetooth, a slow network…).
struct LyricsOffsetRow: View {
    @Binding var offsetMs: Int
    @EnvironmentObject private var theme: ThemeStore

    private var range: ClosedRange<Int> { AppPreferences.lyricsOffsetRange }
    private var step: Int { AppPreferences.lyricsOffsetStep }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.m) {
                Text("Sincronía de las letras")
                    .textStyle(.settingsOptionTitle)
                Spacer(minLength: 0)
                if offsetMs != 0 {
                    Button("Restablecer") { offsetMs = 0 }
                        .buttonStyle(SubtleButtonStyle(height: Metrics.minTouchTarget,
                                                       cornerRadius: Metrics.minTouchTarget / 2))
                }
                stepButton(systemName: "minus", label: "Mostrar las letras más tarde",
                           isEnabled: offsetMs > range.lowerBound) { offsetMs -= step }
                Text(Self.valueText(offsetMs))
                    .textStyle(.settingsOptionTitle)
                    .monospacedDigit()
                    .frame(minWidth: 64)
                    .accessibilityHidden(true)
                stepButton(systemName: "plus", label: "Mostrar las letras antes",
                           isEnabled: offsetMs < range.upperBound) { offsetMs += step }
            }
            Text(Self.explanation(offsetMs))
                .textStyle(.helper)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(Self.explanation(offsetMs)))
    }

    private func stepButton(systemName: String, label: LocalizedStringKey, isEnabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: Metrics.minTouchTarget, height: Metrics.minTouchTarget)
                .background(Circle().fill(Palette.subtleSurface))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Palette.disabledControlOpacity)
        .accessibilityLabel(Text(label))
    }

    /// "0,0 s", "+0,3 s", "−1,5 s".
    static func valueText(_ offsetMs: Int) -> String {
        let seconds = (Double(abs(offsetMs)) / 1000)
            .formatted(.number.precision(.fractionLength(1)))
        switch offsetMs {
        case 0: return seconds + " s"
        case 1...: return "+" + seconds + " s"
        default: return "−" + seconds + " s"
        }
    }

    static func explanation(_ offsetMs: Int) -> LocalizedStringResource {
        let seconds = (Double(abs(offsetMs)) / 1000)
            .formatted(.number.precision(.fractionLength(1)))
        switch offsetMs {
        case 0: return "Sin ajuste. Si las letras van tarde, tocá +; si se adelantan, tocá −."
        case 1...: return "Las letras se muestran \(seconds) s antes."
        default: return "Las letras se muestran \(seconds) s más tarde."
        }
    }
}
