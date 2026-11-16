import Foundation

/// Reads and writes the Client ID and the OAuth tokens in a `SecureStore` (the Keychain in
/// the app). Nothing here is ever written to `UserDefaults` or logged.
struct CredentialStore: Sendable {
    private enum Key {
        static let clientID = "spotify.clientID"
        static let tokens = "spotify.tokens"
    }

    let store: any SecureStore

    init(store: any SecureStore) {
        self.store = store
    }

    func clientID() throws -> String? {
        guard let data = try store.data(forKey: Key.clientID) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setClientID(_ clientID: String) throws {
        try store.set(Data(clientID.utf8), forKey: Key.clientID)
    }

    func tokens() throws -> OAuthTokens? {
        guard let data = try store.data(forKey: Key.tokens) else { return nil }
        // A token blob we cannot read (for example, from a future format) is the same as
        // being logged out: the user just connects again.
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    func setTokens(_ tokens: OAuthTokens) throws {
        try store.set(JSONEncoder().encode(tokens), forKey: Key.tokens)
    }

    func removeTokens() throws {
        try store.removeValue(forKey: Key.tokens)
    }
}
