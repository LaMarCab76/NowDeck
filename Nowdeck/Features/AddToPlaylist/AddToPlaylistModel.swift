import SwiftUI

/// A playlist the user can add items to: one they own, or a collaborative one.
struct EditablePlaylist: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var imageURL: URL?
    var itemCount: Int?
    /// Someone else owns it, but its owner lets others edit it.
    var isCollaborative: Bool

    /// The playlists of `GET /me/playlists` that `userID` can edit, in Spotify's order (the
    /// one the user sees in their library). Playlists without an ID or a name are skipped,
    /// and a playlist listed twice is shown once.
    ///
    /// Owned playlists are editable; others only when `collaborative` is `true`. A playlist
    /// followed from someone else is not: Spotify would answer `403`.
    static func editable(from playlists: [SimplifiedPlaylist],
                         userID: String) -> [EditablePlaylist] {
        var seen = Set<String>()
        var result: [EditablePlaylist] = []
        for playlist in playlists {
            guard let id = playlist.id, !id.isEmpty,
                  let name = playlist.name, !name.isEmpty,
                  seen.insert(id).inserted
            else { continue }
            let isOwned = playlist.owner?.id == userID
            let isCollaborative = playlist.collaborative == true
            guard isOwned || isCollaborative else { continue }
            result.append(EditablePlaylist(
                id: id, name: name,
                imageURL: QueueEntry.thumbnail(playlist.images ?? []),
                itemCount: playlist.itemCount,
                isCollaborative: isCollaborative && !isOwned))
        }
        return result
    }
}

/// What the user can do about the playlist-editing permission, which sessions from before
/// 2026-11-18 do not have (`SpotifyAuthorization.playlistEditingScopes`).
struct PlaylistEditingAccess {
    enum Failure: Equatable {
        /// The user closed the login page.
        case cancelled
        /// The user tapped "Cancel" on Spotify's consent page.
        case denied
        /// The account that logged in is not in the app's Users Management.
        case notAllowlisted
        /// The user logged in with another Spotify account than the one in use.
        case differentAccount
        case offline
        case failed
    }

    enum Grant: Equatable {
        case granted
        case missing
        /// Spotify sent no `scope` with the stored tokens.
        case unknown
    }

    /// Whether the stored session includes the scopes.
    var grant: @MainActor () -> Grant
    /// Opens Spotify's login again, asking for every scope. `nil` when it worked.
    var request: @MainActor () async -> Failure?

    /// For previews and tests.
    static let granted = PlaylistEditingAccess(grant: { .granted }, request: { nil })
}

/// Why something in the sheet failed.
enum AddToPlaylistProblem: Equatable {
    /// `403` while reading the list (Premium or Users Management, as everywhere else).
    case forbidden
    /// `429`. The API client already waits `Retry-After` before calling again.
    case rateLimited
    /// No connection, timeouts or `5xx`.
    case connection
    case unknown
    /// `403` while adding: the playlist is no longer editable, or the session lacks the
    /// scopes even though it says it has them.
    case addForbidden
    /// `404` while adding: the playlist was deleted.
    case addNotFound
    /// Asking for the new permission failed.
    case permission(PlaylistEditingAccess.Failure)

    init(_ error: Error, whileAdding: Bool = false) {
        switch error {
        case SpotifyAPIError.forbidden: self = whileAdding ? .addForbidden : .forbidden
        case SpotifyAPIError.notFound where whileAdding: self = .addNotFound
        case SpotifyAPIError.rateLimited: self = .rateLimited
        case SpotifyAPIError.network, SpotifyAPIError.server: self = .connection
        default: self = .unknown
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .forbidden:
            return "Spotify rechazó el pedido. Revisá que tu cuenta tenga Premium y siga en Users Management de tu app."
        case .rateLimited:
            return "Spotify pide esperar un momento. Probá de nuevo en unos segundos."
        case .connection:
            return "No hay conexión con Spotify. Revisá internet y probá de nuevo."
        case .unknown:
            return "Algo salió mal. Probá de nuevo."
        case .addForbidden:
            return "Spotify no dejó agregarlo. Puede que ya no puedas editar esa playlist."
        case .addNotFound:
            return "Esa playlist ya no existe en Spotify."
        case .permission(.cancelled):
            return "Se cerró la página de Spotify antes de terminar."
        case .permission(.denied):
            return "Para agregar temas, aceptá el permiso en Spotify."
        case .permission(.notAllowlisted):
            return "Spotify no deja usar tu app con esa cuenta. Entrá con la misma cuenta de siempre."
        case .permission(.differentAccount):
            return "Entraste con otra cuenta de Spotify. Probá de nuevo con la que usás en Nowdeck."
        case .permission(.offline):
            return "No hay conexión a internet. Revisala y probá de nuevo."
        case .permission(.failed):
            return "No pudimos conectar con Spotify. Probá de nuevo en un rato."
        }
    }
}

/// Agregar a una playlist (owner's request, 2026-11-18): the playlists the user can edit,
/// and adding the item that was playing when the sheet opened to any of them.
///
/// One model lives as long as the player (`PlayerModel.playlists`), so that:
/// - the list is read once and reused for a while (`maximumListAge`) instead of on every
///   opening: it can take several requests (50 playlists each), and the quota is shared
///   with the player's polling;
/// - what was added stays marked when the sheet opens again for the same item, which also
///   keeps an accidental second tap from adding a duplicate.
///
/// Removing is not offered: `DELETE /playlists/{id}/items` identifies items by URI only and
/// does not document what happens to earlier copies of the same track.
@MainActor
final class AddToPlaylistModel: ObservableObject {
    enum RowState: Equatable {
        case idle
        case adding
        case added
        case failed
    }

    /// How long a list read stays fresh before an opening reads it again.
    static let maximumListAge: TimeInterval = 5 * 60

    /// `nil` until the first answer arrives.
    @Published private(set) var playlists: [EditablePlaylist]?
    /// The last problem, shown until the next successful action.
    @Published private(set) var problem: AddToPlaylistProblem?
    @Published private(set) var isLoading = false
    /// The session lacks the playlist-editing scopes: the sheet asks for them first.
    @Published private(set) var needsPermission = false
    @Published private(set) var isRequestingPermission = false
    /// The item the sheet adds (the one playing when it opened).
    @Published private(set) var targetURI: String?
    /// Adds in flight or failed, by `"<uri>|<playlist id>"`. Done adds live in `added`.
    /// In-flight ones survive closing the sheet: the request keeps going, and the row must
    /// not look tappable when the sheet opens again for the same item.
    @Published private var pending: [String: RowState] = [:]
    /// `"<uri>|<playlist id>"` of every add that worked while the app was open.
    @Published private var added: Set<String> = []

    private let api: SpotifyAPI
    private let now: () -> Date
    private var access = PlaylistEditingAccess.granted
    private var userID: String?
    private var loadedAt: Date?
    private var loadTask: Task<Void, Never>?

    init(api: SpotifyAPI, now: @escaping () -> Date = { Date() }) {
        self.api = api
        self.now = now
    }

    /// Called when the sheet opens for `uri`. Clears what the last opening left.
    func open(for uri: String, access: PlaylistEditingAccess) {
        targetURI = uri
        self.access = access
        // Failures are news of the last opening; adds still in flight are kept.
        pending = pending.filter { $0.value == .adding }
        problem = nil
        needsPermission = access.grant() == .missing
    }

    func state(of playlist: EditablePlaylist) -> RowState {
        guard let targetURI else { return .idle }
        let key = Self.key(uri: targetURI, playlistID: playlist.id)
        if added.contains(key) { return .added }
        return pending[key] ?? .idle
    }

    /// Reads the list unless a recent one is on hand. `force` (pull to refresh, Reintentar)
    /// always reads. A call while a read is running waits for that read.
    func load(force: Bool = false) async {
        if let loadTask {
            await loadTask.value
            return
        }
        if !force, playlists != nil, let loadedAt,
           now().timeIntervalSince(loadedAt) < Self.maximumListAge {
            return
        }
        let task = Task { await fetch() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func fetch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let userID: String
            if let known = self.userID {
                userID = known
            } else {
                userID = try await api.currentUserID()
                self.userID = userID
            }
            let all = try await api.allSavedPlaylists()
            playlists = EditablePlaylist.editable(from: all, userID: userID)
            loadedAt = now()
            if !Self.isAddProblem(problem) { problem = nil }
        } catch is CancellationError {
            return
        } catch {
            problem = AddToPlaylistProblem(error)
        }
    }

    /// Adds the target item to `playlist`. Does nothing while it is being added or once it
    /// was added.
    func add(to playlist: EditablePlaylist) async {
        guard let uri = targetURI, !needsPermission else { return }
        let state = state(of: playlist)
        guard state == .idle || state == .failed else { return }

        let key = Self.key(uri: uri, playlistID: playlist.id)
        pending[key] = .adding
        do {
            try await api.addToPlaylist(playlistID: playlist.id, uri: uri)
            added.insert(key)
            pending[key] = nil
            bumpCount(of: playlist.id)
            // Whatever failed before (this row or another), the last action worked.
            problem = nil
            UIAccessibility.post(notification: .announcement,
                                 argument: String(localized: "Agregado a \(playlist.name)"))
        } catch is CancellationError {
            pending[key] = nil
        } catch {
            pending[key] = .failed
            if case SpotifyAPIError.forbidden = error, access.grant() != .granted {
                // The session lacks the scopes, or may lack them (unknown): ask for them.
                needsPermission = true
            }
            problem = AddToPlaylistProblem(error, whileAdding: true)
        }
    }

    /// Opens Spotify's login to grant the playlist-editing scopes.
    func requestPermission() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        if let failure = await access.request() {
            problem = .permission(failure)
        } else {
            needsPermission = false
            problem = nil
        }
    }

    // MARK: Helpers

    private func bumpCount(of playlistID: String) {
        guard var list = playlists, let index = list.firstIndex(where: { $0.id == playlistID }),
              let count = list[index].itemCount
        else { return }
        list[index].itemCount = count + 1
        playlists = list
    }

    private static func key(uri: String, playlistID: String) -> String {
        "\(uri)|\(playlistID)"
    }

    private static func isAddProblem(_ problem: AddToPlaylistProblem?) -> Bool {
        switch problem {
        case .addForbidden, .addNotFound, .permission: return true
        default: return false
        }
    }
}
