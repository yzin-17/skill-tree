import Foundation
import Security

public struct ClientConfiguration: Codable, Sendable {
    public let baseURL: URL
    public let certificateSHA256: String
    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url", certificateSHA256 = "certificate_sha256"
    }
}

public struct Health: Codable, Sendable, Equatable {
    public let service: String
    public let status: String
    public let version: String
    public let database: String
}

public struct APIError: Error, Codable, Sendable, LocalizedError {
    public let code: String
    public let message: String
    public let httpStatus: Int?
    public var errorDescription: String? { message }
    public init(code: String, message: String, httpStatus: Int? = nil) { self.code = code; self.message = message; self.httpStatus = httpStatus }
}

private struct Envelope<Value: Decodable>: Decodable { let data: Value }
private struct ErrorEnvelope: Decodable { let error: APIError }

public final class LocalCertificateDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let certificate: Data
    private let host: String
    private let baseURL: URL
    private let allowSystemTrust: Bool
    public init(certificate: Data, baseURL: URL, allowSystemTrust: Bool = false) {
        self.certificate = certificate; self.baseURL = baseURL
        self.host = (baseURL.host ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        self.allowSystemTrust = allowSystemTrust
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == host.lowercased(),
              let trust = challenge.protectionSpace.serverTrust else {
            if ProcessInfo.processInfo.environment["SKILLATLAS_TLS_DIAGNOSTIC"] == "1" { print("TLS 主机、证书或认证方法不匹配：\(challenge.protectionSpace.host)") }
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first, SecCertificateCopyData(leaf) as Data == certificate,
              let anchor = SecCertificateCreateWithData(nil, certificate as CFData) else {
            completionHandler(allowSystemTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil); return
        }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        SecTrustSetAnchorCertificates(trust, [anchor] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else {
            if ProcessInfo.processInfo.environment["SKILLATLAS_TLS_DIAGNOSTIC"] == "1" { print("TLS 验证：\(String(describing: trustError))") }
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map { BackendAddress.sameOrigin($0, baseURL) } == true ? request : nil)
    }
}

public final class APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let ownsSession: Bool
    private let lifecycle = ClientLifecycle()

    public init(baseURL: URL, certificate: Data, allowSystemTrust: Bool = false) {
        self.baseURL = baseURL
        self.ownsSession = true
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration,
            delegate: LocalCertificateDelegate(certificate: certificate, baseURL: baseURL, allowSystemTrust: allowSystemTrust), delegateQueue: nil)
    }

    public init(baseURL: URL, session: URLSession) { self.baseURL = baseURL; self.session = session; self.ownsSession = false }

    deinit { if ownsSession { session.invalidateAndCancel() } }

    public static func bundled(_ bundle: Bundle = .main) throws -> APIClient {
        let environment = try BackendEnvironment.bundled(bundle)
        return environment.client(for: environment.defaultAddress)
    }

    public func invalidate() {
        lifecycle.close()
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    public func checkHealth() async throws -> Health {
        let value: Health = try await request("/health")
        guard value.service == "Skill Atlas", value.status == "ok", value.database == "ready" else {
            throw APIError(code: "unexpected_backend", message: "该地址未返回可用的 Skill Atlas 服务状态。")
        }
        return value
    }

    public func request<Response: Decodable & Sendable>(_ path: String, method: String = "GET", token: String? = nil,
                                                        body: Data? = nil, as type: Response.Type = Response.self) async throws -> Response {
        guard !lifecycle.isClosed else { throw CancellationError() }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL, BackendAddress.sameOrigin(url, baseURL) else {
            throw APIError(code: "invalid_url", message: "请求必须使用配置的同一 HTTPS 后端。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard !lifecycle.isClosed else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse else { throw APIError(code: "invalid_response", message: "服务响应无法识别。") }
        guard (200..<300).contains(response.statusCode) else {
            if let error = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) { throw APIError(code: error.error.code, message: error.error.message, httpStatus: response.statusCode) }
            throw APIError(code: "http_\(response.statusCode)", message: "服务暂不可用，请稍后重试。", httpStatus: response.statusCode)
        }
        return try Self.decoder().decode(Envelope<Response>.self, from: data).data
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "时间格式无效"))
            }
            return date
        }
        return decoder
    }

    public static func body<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(value)
    }
}

private final class ClientLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    var isClosed: Bool { lock.withLock { closed } }
    func close() { lock.withLock { closed = true } }
}
