import Foundation
import Security
import LocalAuthentication

public protocol SessionVault: Sendable {
    func read() throws -> AccountSession?
    func save(_ session: AccountSession, allowInteraction: Bool) throws
    func clear() throws
}

public struct KeychainSessionVault: SessionVault {
    public let service: String
    public init(service: String = "local.skillatlas.session") { self.service = service }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current-session", kSecAttrSynchronizable as String: false] }
    private func query(allowInteraction: Bool) -> [String: Any] {
        var request = query
        let context = LAContext(); context.interactionNotAllowed = !allowInteraction
        request[kSecUseAuthenticationContext as String] = context
        return request
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw APIError(code: "keychain_\(status)", message: "无法访问钥匙串，请解锁本机钥匙串后重试。") }
    }
    public func read() throws -> AccountSession? {
        var request = query(allowInteraction: false)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw APIError(code: "keychain_data", message: "登录信息无法读取，请重新登录。") }
        return try JSONDecoder().decode(AccountSession.self, from: data)
    }
    public func save(_ session: AccountSession, allowInteraction: Bool = false) throws {
        let data = try JSONEncoder().encode(session)
        let values = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
        let request = query(allowInteraction: allowInteraction)
        let status = SecItemUpdate(request as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = request; values.forEach { item[$0.key] = $0.value }
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    public func clear() throws {
        let status = SecItemDelete(query(allowInteraction: false) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}
