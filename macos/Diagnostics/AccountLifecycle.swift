import Foundation

@main
struct AccountLifecycle {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let config = try JSONDecoder().decode(ClientConfiguration.self, from: Data(contentsOf: root.appendingPathComponent("client-config.json")))
        let client = APIClient(baseURL: config.baseURL, certificate: try Data(contentsOf: root.appendingPathComponent("tls/cert.der")))
        let suffix = UUID().uuidString.lowercased()
        let vault = KeychainSessionVault(service: "local.skillatlas.acceptance.\(suffix)")
        defer { try? vault.clear() }
        let email = "native-acceptance-\(suffix)@example.invalid"
        let password = UUID().uuidString + UUID().uuidString
        let controller = AccountController(client: client, vault: vault)
        await controller.restore()
        guard controller.user == nil else { throw APIError(code: "acceptance", message: "测试钥匙串未隔离") }
        await controller.authenticate(email: email, password: password, create: true)
        guard let first = controller.session else { throw APIError(code: "acceptance", message: "原生注册失败：\(controller.errorMessage ?? "")") }
        let resumed = AccountController(client: client, vault: vault)
        await resumed.restore()
        guard resumed.user?.id == first.user.id, !resumed.isOffline else { throw APIError(code: "acceptance", message: "钥匙串恢复验证失败") }
        await resumed.signOut()
        guard resumed.user == nil, try vault.read() == nil else { throw APIError(code: "acceptance", message: "退出清除失败") }
        do { let _: AccountUser = try await client.request("/v1/me", token: first.token); throw APIError(code: "acceptance", message: "已退出令牌仍有效") }
        catch let error as APIError where error.code == "unauthenticated" {}
        let login = AccountController(client: client, vault: vault)
        await login.authenticate(email: email, password: "wrong-password-for-check", create: false)
        guard login.user == nil, login.errorMessage != nil else { throw APIError(code: "acceptance", message: "错误密码反馈失败") }
        await login.authenticate(email: email, password: password, create: false)
        guard login.user?.id == first.user.id else { throw APIError(code: "acceptance", message: "再次登录身份不一致") }
        await login.signOut()
        let expired = AccountSession(user: first.user, token: "expired-test-value", expiresAt: .distantPast)
        try vault.save(expired)
        let expiration = AccountController(client: client, vault: vault)
        await expiration.restore()
        guard expiration.user == nil, try vault.read() == nil else { throw APIError(code: "acceptance", message: "过期登录未清理") }
        let record = ["id":first.user.id,"email":email,"purpose":"原生账号生命周期验收，未创建业务记录"]
        let directory = root.appendingPathComponent("acceptance", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("account-\(suffix).json"))
        print("原生账号验证通过：注册、Keychain 恢复、退出撤销、错误密码、再次登录、过期清除；所有测试会话已退出。")
    }
}
