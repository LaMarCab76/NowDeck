import SwiftUI

/// The Buscar tab: the search field and its help line (`Biblioteca.dc.html`).
///
/// The results screen is not designed yet (docs/01-producto.md, "Fuera de alcance"), so
/// submitting a search does not call the API: it only says that results are not available
/// yet. `SpotifyAPI.search(_:)` and `SearchQuery` are ready for when the owner approves a
/// results design.
struct LibrarySearchView: View {
    @State private var text = ""
    @State private var submittedText: String?
    @FocusState private var isFocused: Bool

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.searchBlockGap) {
            field
            Text(helpText)
                .textStyle(.searchHelp)
                .foregroundStyle(theme.palette.bodyText.color)
                .frame(maxWidth: Layout.searchHelpMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(submittedText == nil ? [] : .updatesFrequently)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Layout.searchBlockHeight, alignment: .top)
    }

    private var field: some View {
        HStack(spacing: Layout.searchFieldIconGap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Layout.searchFieldIconSize - 3, weight: .bold))
                .foregroundStyle(theme.palette.bodyText.color)
                .frame(width: Layout.searchFieldIconSize, height: Layout.searchFieldIconSize)
                .accessibilityHidden(true)

            // `String()`: an empty, non-localized title (a literal would add an empty key
            // to the String Catalog).
            TextField(String(), text: $text)
                .textStyle(.searchInput)
                .foregroundStyle(theme.palette.text.color)
                .tint(theme.palette.accent.color)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel(Text("Buscar en Spotify"))
                // The placeholder is drawn by hand: iOS 16 does not color a TextField
                // prompt, and the mockup uses the `etiqueta` color.
                .background(alignment: .leading) {
                    if text.isEmpty {
                        Text("Temas, artistas, álbumes, podcasts o audiolibros")
                            .textStyle(.searchInput)
                            .foregroundStyle(theme.palette.label.color)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                }
                .onSubmit {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    submittedText = trimmed.isEmpty ? nil : trimmed
                }
                .onChange(of: text) { _ in submittedText = nil }
        }
        .padding(.horizontal, Layout.searchFieldPadding)
        .frame(height: Layout.searchFieldHeight)
        .background(Capsule().fill(Palette.searchField))
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }

    private var helpText: LocalizedStringKey {
        if submittedText == nil {
            return "Tocá un resultado y empieza a sonar en el dispositivo activo."
        }
        return "Los resultados de búsqueda todavía no están disponibles en esta versión."
    }
}
