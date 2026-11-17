import SwiftUI

/// The device list as the sheet shows it (Dispositivos.dc.html): the active device in the
/// header, and the rest below "ELEGÍ UN DISPOSITIVO".
///
/// Order of the rest: devices that accept a transfer first, then the ones that don't
/// (restricted or without an ID); each group by name, so the rows don't jump around when
/// Spotify returns them in another order after "Actualizar lista".
struct DeviceChoices: Equatable {
    /// The device with `is_active`, if any. When Spotify marks more than one (it should not),
    /// the first one wins.
    var current: SpotifyDevice?
    var others: [SpotifyDevice]

    init(devices: [SpotifyDevice]) {
        let current = devices.first(where: \.isActive)
        self.current = current
        var others = devices
        if let index = devices.firstIndex(where: \.isActive) {
            others.remove(at: index)
        }
        self.others = others.sorted(by: Self.listOrder)
    }

    /// Nothing at all to show.
    var isEmpty: Bool { current == nil && others.isEmpty }

    private static func listOrder(_ a: SpotifyDevice, _ b: SpotifyDevice) -> Bool {
        if a.acceptsTransfer != b.acceptsTransfer { return a.acceptsTransfer }
        switch a.name.localizedStandardCompare(b.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return (a.id ?? "") < (b.id ?? "")
        }
    }
}

extension SpotifyDevice {
    /// Whether playback can be moved here. Restricted devices accept no Web API commands,
    /// and a device without an ID cannot be named in the request.
    var acceptsTransfer: Bool {
        guard let id, !id.isEmpty else { return false }
        return !isRestricted
    }

    var isInPrivateSession: Bool { isPrivateSession == true }
}

/// The name of a Spotify Connect device type, in the UI's language. Spotify documents the
/// field only by example ("computer", "smartphone", "speaker") and the case varies, so the
/// match ignores case and unknown types get a generic name.
enum DeviceTypeName {
    static func key(for type: String) -> LocalizedStringKey {
        switch type.lowercased() {
        case "computer": return "Computadora"
        case "smartphone": return "Teléfono"
        case "tablet": return "Tablet"
        case "speaker": return "Parlante"
        case "tv": return "TV"
        case "avr": return "Receptor de audio"
        case "stb": return "Decodificador"
        case "audiodongle": return "Adaptador de audio"
        case "gameconsole": return "Consola"
        case "castvideo": return "Transmisión de video"
        case "castaudio": return "Transmisión de audio"
        case "automobile": return "Auto"
        case "smartwatch": return "Reloj"
        default: return "Dispositivo"
        }
    }
}

/// What went wrong while reading the list or moving playback, reduced to what the sheet
/// tells the user.
enum DevicesProblem: Equatable {
    /// `403`: Spotify does not tell apart a user outside *Users Management*, the owner's
    /// lapsed Premium and a user without Premium (docs/03), so one message covers them.
    case forbidden
    /// `429`. The API client already waits `Retry-After` before calling again.
    case rateLimited
    /// No connection, timeouts or `5xx`.
    case connection
    /// `404` on a transfer: the device went away (or went to sleep) since the list loaded.
    case deviceGone
    /// Anything else.
    case unknown

    init(_ error: Error, duringTransfer: Bool) {
        switch error {
        case SpotifyAPIError.forbidden:
            self = .forbidden
        case SpotifyAPIError.rateLimited:
            self = .rateLimited
        case SpotifyAPIError.network, SpotifyAPIError.server:
            self = .connection
        case SpotifyAPIError.notFound where duringTransfer:
            self = .deviceGone
        default:
            self = .unknown
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
        case .deviceGone:
            return "Ese dispositivo ya no está disponible. Actualizamos la lista."
        case .unknown:
            return "Algo salió mal. Probá de nuevo."
        }
    }
}
