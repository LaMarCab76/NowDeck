import Foundation

/// Talks to `accounts.spotify.com/api/token`: exchanges the authorization code and refreshes
/// tokens. No Client Secret: PKCE public client.
struct SpotifyAccountsClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func exchangeCode(_ code: String, codeVerifier: String, clientID: String) async throws -> TokenResponse {
        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyAuthorization.redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier,
        ])
    }

    func refresh(refreshToken: String, clientID: String) async throws -> TokenResponse {
        try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
    }

    private func requestToken(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: SpotifyAuthorization.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(fields)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw AuthError.network(error.code)
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidTokenResponse }

        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
            switch body?.error {
            case "invalid_grant": throw AuthError.invalidGrant
            case "invalid_client": throw AuthError.invalidClient
            default: throw AuthError.tokenRequestFailed(status: http.statusCode, error: body?.error)
            }
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.invalidTokenResponse
        }
    }

    /// `application/x-www-form-urlencoded`, with keys sorted so requests are predictable in
    /// tests.
    static func formEncoded(_ fields: [String: String]) -> Data {
        // Form encoding only leaves unreserved characters as they are.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = fields.sorted { $0.key < $1.key }.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
