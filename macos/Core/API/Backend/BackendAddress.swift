import Foundation
import CryptoKit

public struct BackendAddress: Hashable, Sendable {
    public let url: URL
    public var text: String { url.absoluteString }

    public init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              var parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              !text.hasSuffix(":"), parts.url != nil else {
            throw APIError(code: "invalid_backend", message: "请输入 HTTPS 服务根地址，例如 https://example.com:8447；地址中不能包含账号、路径、查询或片段。")
        }
        parts.scheme = "https"; parts.host = host.lowercased(); parts.path = ""
        if parts.port == 443 { parts.port = nil }
        guard let url = parts.url else { throw APIError(code: "invalid_backend", message: "后端地址无效。") }
        self.url = url
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard lhs.user == nil, lhs.password == nil, rhs.user == nil, rhs.password == nil,
              lhs.scheme?.lowercased() == "https", rhs.scheme?.lowercased() == "https",
              let a = lhs.host?.lowercased(), let b = rhs.host?.lowercased() else { return false }
        return a == b && (lhs.port ?? 443) == (rhs.port ?? 443)
    }
}

public struct BackendScope: Equatable, Sendable {
    public let identifier: String
    public var isDefault: Bool { identifier == "bundled" }
    public var rememberKey: String { isDefault ? "account.rememberLogin" : "account.rememberLogin.\(identifier)" }
    public var vaultService: String { isDefault ? "local.skillatlas.session" : "local.skillatlas.session.\(identifier)" }

    public init(address: BackendAddress, defaultAddress: BackendAddress) {
        identifier = address == defaultAddress ? "bundled" : SHA256.hash(data: Data(address.text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func directory(in root: URL) -> URL {
        isDefault ? root : root.appendingPathComponent("backends", isDirectory: true).appendingPathComponent(identifier, isDirectory: true)
    }
}

@MainActor
public struct BackendPreferences {
    public static let addressKey = "backend.address"
    public let defaultAddress: BackendAddress
    private let preferences: UserDefaults
    public init(defaultAddress: BackendAddress, preferences: UserDefaults = .standard) {
        self.defaultAddress = defaultAddress; self.preferences = preferences
    }
    public var current: BackendAddress {
        guard let saved = preferences.string(forKey: Self.addressKey), let address = try? BackendAddress(saved) else { return defaultAddress }
        return address
    }
    public func save(_ address: BackendAddress) {
        if address == defaultAddress { preferences.removeObject(forKey: Self.addressKey) }
        else { preferences.set(address.text, forKey: Self.addressKey) }
    }
}

public struct BackendEnvironment: Sendable {
    public let defaultAddress: BackendAddress
    private let certificate: Data
    public static func bundled(_ bundle: Bundle = .main) throws -> Self {
        guard let configURL = bundle.url(forResource: "client-config", withExtension: "json"),
              let certURL = bundle.url(forResource: "cert", withExtension: "der") else {
            throw APIError(code: "configuration_missing", message: "连接配置缺失，请重新构建应用。")
        }
        let config = try JSONDecoder().decode(ClientConfiguration.self, from: Data(contentsOf: configURL))
        return Self(defaultAddress: try BackendAddress(config.baseURL.absoluteString), certificate: try Data(contentsOf: certURL))
    }
    public func client(for address: BackendAddress) -> APIClient {
        APIClient(baseURL: address.url, certificate: certificate, allowSystemTrust: address != defaultAddress)
    }
}
