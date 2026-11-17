import SwiftUI
import UIKit

/// A theme waiting in the import sheet.
struct ThemeImportRequest: Identifiable, Equatable {
    let id = UUID()
    /// File name, or a description of the source (clipboard).
    let sourceName: String
    /// The text shown in the JSON box. Only displayed, never interpreted.
    let contents: String
    let result: Result<ValidatedTheme, ThemeImportError>
}

/// Collects themes from the three entry points (docs/05, "Importar") and decides which
/// screen shows the import sheet.
///
/// - Files opened from outside the app (Files, AirDrop): `handleOpenURL(_:)`, from `onOpenURL`.
/// - The file picker in Settings: `importFile(_:)`, from `.fileImporter`.
/// - The clipboard: `importFromClipboard()`.
///
/// The sheet is a full-screen cover, and only the top-most screen can present one. Each
/// screen that can show it applies `.themeImportPresenter()`, which registers it here; the
/// last registered one (Settings over the player, for example) presents the request.
@MainActor
final class ThemeImportCoordinator: ObservableObject {
    @Published var request: ThemeImportRequest?
    @Published private(set) var presenters: [UUID] = []

    var activePresenter: UUID? { presenters.last }

    // MARK: Entry points

    /// `nowdeck://callback` (the OAuth redirect) is handled by `ASWebAuthenticationSession`
    /// and never needs this app's URL handling; any URL that is not a file is ignored here.
    func handleOpenURL(_ url: URL) {
        guard url.isFileURL else { return }
        importFile(at: url)
        removeInboxCopy(url)
    }

    func importFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importFile(at: url)
        case .failure:
            // The picker reports a failure only when it cannot open the file.
            request = ThemeImportRequest(sourceName: "", contents: "",
                                         result: .failure(.unreadable))
        }
    }

    /// Reading the clipboard from code makes iOS ask "Allow Paste?". That is expected here:
    /// the user just chose "Pegar desde el portapapeles".
    /// The pasteboard is a parameter only for tests (a private pasteboard does not ask).
    func importFromClipboard(_ pasteboard: UIPasteboard = .general) {
        let source = String(localized: "Portapapeles")
        guard let text = pasteboard.string, !text.isEmpty else {
            request = ThemeImportRequest(sourceName: source, contents: "",
                                         result: .failure(.emptyClipboard))
            return
        }
        importData(Data(text.utf8), sourceName: source)
    }

    func importFile(at url: URL) {
        let name = url.lastPathComponent
        do {
            importData(try ThemeFile.readForImport(from: url), sourceName: name)
        } catch {
            request = ThemeImportRequest(sourceName: name, contents: "", result: .failure(.unreadable))
        }
    }

    func importData(_ data: Data, sourceName: String) {
        request = ThemeImportRequest(sourceName: sourceName,
                                     contents: Self.displayText(for: data),
                                     result: ThemeValidator.validate(data))
    }

    func dismiss() {
        request = nil
    }

    // MARK: Presenters

    func register(_ presenter: UUID) {
        presenters.removeAll { $0 == presenter }
        presenters.append(presenter)
    }

    func unregister(_ presenter: UUID) {
        presenters.removeAll { $0 == presenter }
    }

    // MARK: Helpers

    /// At most the first 16 KB, decoded as UTF-8 (invalid bytes become "�").
    static func displayText(for data: Data) -> String {
        String(decoding: data.prefix(ThemeValidator.maximumSize), as: UTF8.self)
    }

    /// Files opened from other apps are copied into `Documents/Inbox` (the app does not open
    /// documents in place). The theme is already read, so the copy is deleted.
    private func removeInboxCopy(_ url: URL) {
        guard let documents = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first
        else { return }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
            .resolvingSymlinksInPath().path
        let file = url.resolvingSymlinksInPath().path
        if file.hasPrefix(inbox + "/") {
            try? FileManager.default.removeItem(atPath: file)
        }
    }
}

// MARK: - Presenting the sheet

private struct ThemeImportPresenter: ViewModifier {
    let isEnabled: Bool
    @EnvironmentObject private var coordinator: ThemeImportCoordinator
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { if isEnabled { coordinator.register(id) } }
            .onDisappear { coordinator.unregister(id) }
            .onChange(of: isEnabled) { enabled in
                if enabled { coordinator.register(id) } else { coordinator.unregister(id) }
            }
            .fullScreenCover(item: requestBinding) { request in
                // Passed explicitly: a cover is a new view hierarchy.
                ThemeImportView(request: request)
                    .environmentObject(coordinator)
                    .environmentObject(themeStore)
            }
    }

    private var requestBinding: Binding<ThemeImportRequest?> {
        Binding(
            get: { coordinator.activePresenter == id ? coordinator.request : nil },
            set: { newValue in
                if newValue == nil, coordinator.activePresenter == id { coordinator.dismiss() }
            }
        )
    }
}

extension View {
    /// Lets this screen show the import sheet when it is the top-most one. `isEnabled: false`
    /// holds requests back (for example during the portrait onboarding); they show up as
    /// soon as a screen can present them.
    func themeImportPresenter(isEnabled: Bool = true) -> some View {
        modifier(ThemeImportPresenter(isEnabled: isEnabled))
    }
}
