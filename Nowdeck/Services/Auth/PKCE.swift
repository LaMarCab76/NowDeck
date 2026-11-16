import CryptoKit
import Foundation
import Security

/// Proof Key for Code Exchange (RFC 7636), as Spotify's PKCE tutorial describes it.
struct PKCE: Equatable, Sendable {
    /// Characters allowed in a code verifier (RFC 7636 "unreserved").
    static let verifierAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static let verifierLengthRange = 43...128

    let verifier: String
    let challenge: String

    /// A new random verifier (64 characters) and its S256 challenge.
    static func generate() throws -> PKCE {
        let verifier = try randomString(length: 64)
        return PKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    /// `BASE64URL(SHA256(verifier))` without `=` padding.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    /// A random string over `verifierAlphabet`, from the system CSPRNG. Also used for the
    /// OAuth `state`.
    static func randomString(length: Int) throws -> String {
        let alphabet = verifierAlphabet
        // 256 is not a multiple of the alphabet size (66), so `byte % 66` would favour the
        // first characters. Bytes at or above the largest multiple (198) are discarded and
        // drawn again (rejection sampling), which keeps every character equally likely.
        let limit = 256 / alphabet.count * alphabet.count
        var characters: [Character] = []
        characters.reserveCapacity(length)
        while characters.count < length {
            for byte in try randomBytes(count: length) where Int(byte) < limit {
                characters.append(alphabet[Int(byte) % alphabet.count])
                if characters.count == length { break }
            }
        }
        return String(characters)
    }

    private static func randomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw PKCEError.randomGenerationFailed(status) }
        return bytes
    }
}

enum PKCEError: Error, Equatable {
    case randomGenerationFailed(OSStatus)
}

extension Data {
    /// Base64url (RFC 4648 §5) without padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
