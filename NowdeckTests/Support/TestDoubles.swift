import Foundation
@testable import Nowdeck

/// In-memory `SecureStore` that replaces the Keychain in tests.
final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(forKey key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func set(_ data: Data, forKey key: String) throws {
        lock.withLock { values[key] = data }
    }

    func removeValue(forKey key: String) throws {
        lock.withLock { values[key] = nil }
    }
}

/// Answers `URLSession` requests from a handler, so tests never reach Spotify.
///
/// Use `StubURLProtocol.session(handler:)` to get a session wired to a handler. Requests are
/// recorded (with their body) so tests can inspect what was sent.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var recorded: [String: [URLRequest]] = [:]

    /// A session whose requests go to `handler`. Each session gets its own id, sent in a
    /// header, so tests do not share state.
    static func session(handler: @escaping Handler) -> (URLSession, StubRecorder) {
        let id = UUID().uuidString
        lock.withLock {
            handlers[id] = handler
            recorded[id] = []
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Stub-ID": id]
        return (URLSession(configuration: configuration), StubRecorder(id: id))
    }

    static func requests(for id: String) -> [URLRequest] {
        lock.withLock { recorded[id] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Stub-ID"),
              let handler = Self.lock.withLock({ Self.handlers[id] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        // URLSession moves the body to a stream; copy it back so tests can read it.
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Data(reading: stream)
        }
        Self.lock.withLock { Self.recorded[id, default: []].append(request) }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

struct StubRecorder: Sendable {
    let id: String
    var requests: [URLRequest] { StubURLProtocol.requests(for: id) }
}

extension HTTPURLResponse {
    static func stub(_ status: Int, url: URL = URL(string: "https://example.com")!) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }
}

extension URLRequest {
    /// The form fields of an `application/x-www-form-urlencoded` body.
    var formFields: [String: String] {
        guard let body = httpBody, let string = String(data: body, encoding: .utf8) else { return [:] }
        var fields: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            fields[parts[0].removingPercentEncoding ?? parts[0]] =
                parts[1].removingPercentEncoding ?? parts[1]
        }
        return fields
    }
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            append(buffer, count: count)
        }
    }
}

/// JSON body of a successful token answer.
func tokenJSON(access: String, refresh: String?, expiresIn: Int = 3600) -> Data {
    var object: [String: Any] = [
        "access_token": access,
        "token_type": "Bearer",
        "scope": "user-read-playback-state",
        "expires_in": expiresIn,
    ]
    if let refresh { object["refresh_token"] = refresh }
    return try! JSONSerialization.data(withJSONObject: object)
}

func tokenErrorJSON(_ error: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["error": error, "error_description": "test"])
}
