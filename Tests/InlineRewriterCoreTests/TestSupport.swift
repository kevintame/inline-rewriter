import Foundation
@testable import InlineRewriterCore

/// A throwaway UserDefaults suite, cleared before use so tests never see each other's data.
func makeTestDefaults() -> UserDefaults {
    let suite = "InlineRewriterCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// In-memory keychain double.
final class InMemoryKeychain: KeychainStoring {
    var values: [String: String] = [:]
    var errorToThrow: Error?

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func readString(account: String) throws -> String? {
        if let errorToThrow { throw errorToThrow }
        return values[account]
    }

    func writeString(_ value: String, account: String) throws {
        if let errorToThrow { throw errorToThrow }
        values[account] = value
    }

    func delete(account: String) throws {
        if let errorToThrow { throw errorToThrow }
        values.removeValue(forKey: account)
    }
}

/// URLProtocol that answers every request from a static handler. Tests that use it run
/// serialized because the handler is shared.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    static func reset() {
        handler = nil
        recordedRequests = []
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// URLSession hands the body to protocols as a stream, so read it back out.
    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        Self.recordedRequests.append(request)
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
