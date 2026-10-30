import Foundation
import Testing
@testable import SkillAtlasCore

@Suite(.serialized) @MainActor
struct LoginPreferenceTests {
    private func setup(remember: Bool = false, vault: LoginTestVault = .init()) -> (AccountController, UserDefaults) {
        LoginTestProtocol.state.reset()
        let defaults = UserDefaults(suiteName: "local.skillatlas.login-tests.\(UUID())")!
        if remember { defaults.set(true, forKey: AccountController.rememberKey) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LoginTestProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://login-test.invalid")!, session: URLSession(configuration: config))
        return (AccountController(client: client, vault: vault, preferences: defaults), defaults)
    }
    private func login(_ account: AccountController, remember: Bool = false, create: Bool = false) async {
        await account.authenticate(email: "fixture@example.invalid", password: "fixture-password", create: create, rememberLogin: remember)
    }

    @Test func defaultStartupIgnoresExistingCredentials() async {
        let vault = LoginTestVault(stored: LoginTestVault.session())
        let (account, defaults) = setup(vault: vault)
        await account.restore()
        #expect(account.user == nil && !account.isRestoring && !account.remembersLogin)
        #expect(defaults.object(forKey: AccountController.rememberKey) == nil)
        #expect(vault.calls.isEmpty && LoginTestProtocol.state.paths.isEmpty)
    }

    @Test func manualLoginTimezoneAndExpiryNeverTouchVault() async throws {
        let vault = LoginTestVault(fails: ["read", "save", "clear"])
        let (account, _) = setup(vault: vault)
        await account.restore(); await login(account)
        #expect(account.token == "fixture-session" && !account.isOffline && !account.remembersLogin)
        try await account.updateTimezone("America/New_York")
        #expect(account.user?.timezone == "America/New_York")
        var savedFocus = false; account.beforeSignOut = { savedFocus = true }
        do { let _: LogoutResult = try await account.request("/private"); Issue.record("401 应退出会话") }
        catch let error as APIError { #expect(error.code == "unauthenticated") }
        #expect(savedFocus && account.session == nil)
        #expect(vault.calls.isEmpty)
    }

    @Test func manualRegistrationAndSignOutNeverTouchVault() async {
        let vault = LoginTestVault()
        let (account, _) = setup(vault: vault)
        await account.restore(); await login(account, create: true)
        var savedFocus = false; account.beforeSignOut = { savedFocus = true }
        await account.signOut()
        #expect(savedFocus && account.session == nil && !account.isBusy)
        #expect(LoginTestProtocol.state.paths == ["/v1/auth/register", "/v1/auth/logout"])
        #expect(vault.calls.isEmpty)
    }

    @Test func optionalSaveFailureKeepsSuccessfulLogin() async {
        let vault = LoginTestVault(fails: ["save"])
        let (account, defaults) = setup(vault: vault)
        await login(account, remember: true)
        #expect(account.token == "fixture-session" && !account.isOffline)
        #expect(!account.remembersLogin && !defaults.bool(forKey: AccountController.rememberKey))
        #expect(account.sessionNotice != nil && account.errorMessage == nil)
        #expect(vault.calls == ["save:interactive"])
        #expect(LoginTestProtocol.state.paths == ["/v1/auth/login"])
    }

    @Test func explicitRememberRestoresWithoutRewritingCredentials() async {
        let vault = LoginTestVault()
        let (account, defaults) = setup(vault: vault)
        await login(account, remember: true)
        #expect(account.remembersLogin && defaults.bool(forKey: AccountController.rememberKey))
        let restored = AccountController(client: nil, vault: vault, preferences: defaults)
        await restored.restore()
        #expect(restored.token == account.token && restored.isOffline)
        #expect(vault.calls == ["save:interactive", "read"])
        await restored.stopRemembering()
        #expect(!restored.remembersLogin && restored.token != nil)
        #expect(vault.calls.last == "clear")
    }

    @Test func restoreReadFailureFallsBackToPasswordLogin() async {
        let vault = LoginTestVault(fails: ["read"])
        let (account, defaults) = setup(remember: true, vault: vault)
        await account.restore()
        #expect(account.session == nil && !account.isRestoring && account.errorMessage != nil)
        #expect(!defaults.bool(forKey: AccountController.rememberKey))
        #expect(vault.calls == ["read"])
    }

    @Test func expiredSavedSessionDoesNotDependOnSuccessfulCleanup() async {
        let vault = LoginTestVault(stored: LoginTestVault.session(expired: true), fails: ["clear"])
        let (account, _) = setup(remember: true, vault: vault)
        await account.restore()
        #expect(account.session == nil && !account.isRestoring && !account.remembersLogin)
        #expect(vault.calls == ["read", "clear"] && LoginTestProtocol.state.paths.isEmpty)
    }

    @Test func serverRejectsRememberedSessionWithoutBlockingLoginForm() async {
        let vault = LoginTestVault(stored: LoginTestVault.session(), fails: ["clear"])
        let (account, _) = setup(remember: true, vault: vault)
        LoginTestProtocol.state.setFailure("/v1/me")
        await account.restore()
        #expect(account.session == nil && !account.isRestoring && !account.remembersLogin)
        #expect(vault.calls == ["read", "clear"])
    }

    @Test func rememberedSignOutSucceedsEvenWhenCleanupFails() async {
        let vault = LoginTestVault(fails: ["clear"])
        let (account, defaults) = setup(vault: vault)
        await login(account, remember: true); await account.signOut()
        #expect(account.session == nil && account.errorMessage == nil && !account.isBusy)
        #expect(!defaults.bool(forKey: AccountController.rememberKey))
        #expect(vault.calls == ["save:interactive", "clear"])
    }

    @Test func failedSignOutOrUnsavedFocusRetainsSession() async {
        let vault = LoginTestVault()
        let (account, _) = setup(vault: vault)
        await login(account)
        account.beforeSignOut = { throw APIError(code: "storage", message: "未保存") }
        await account.signOut()
        #expect(account.session != nil && LoginTestProtocol.state.paths == ["/v1/auth/login"])
        account.beforeSignOut = nil; LoginTestProtocol.state.setFailure("/v1/auth/logout")
        await account.signOut()
        #expect(account.session != nil && account.errorMessage != nil && vault.calls.isEmpty)
    }

    @Test func cancelledRestoreCannotOverwriteNewManualLogin() async {
        let gate = DispatchSemaphore(value: 0)
        let vault = LoginTestVault(stored: LoginTestVault.session(), readGate: gate)
        let (account, _) = setup(remember: true, vault: vault)
        let restoring = Task { await account.restore() }
        for _ in 0..<100 where vault.calls.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(vault.calls == ["read"])
        account.usePasswordLogin()
        await login(account)
        gate.signal(); await restoring.value
        #expect(account.token == "fixture-session" && !account.isRestoring && !account.remembersLogin)
        #expect(vault.calls == ["read"])
        #expect(LoginTestProtocol.state.paths == ["/v1/auth/login"])
    }

    @Test func timezonePersistenceFailurePreservesServerUpdate() async throws {
        let vault = LoginTestVault(stored: LoginTestVault.session(), fails: ["save"])
        let (account, _) = setup(remember: true, vault: vault)
        await account.restore()
        #expect(account.session != nil && !account.isOffline)
        try await account.updateTimezone("America/New_York")
        #expect(account.user?.timezone == "America/New_York" && !account.remembersLogin)
        #expect(vault.calls == ["read", "save:silent"])
        #expect(account.sessionNotice != nil)
    }
    @Test func backendPreferencesStaySeparateAndDeactivationKeepsRememberedScope() async throws {
        LoginTestProtocol.state.reset()
        let name = "local.skillatlas.backend-login-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AccountController.rememberKey)
        let original = try BackendAddress("https://localhost:8447")
        let scope = BackendScope(address: try BackendAddress("https://127.0.0.1:8447"), defaultAddress: original)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [LoginTestProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://login-test.invalid")!, session: URLSession(configuration: config))
        let vault = LoginTestVault(stored: LoginTestVault.session())
        let account = AccountController(client: client, vault: vault, preferences: defaults, rememberKey: scope.rememberKey)
        await account.restore()
        #expect(vault.calls.isEmpty && account.session == nil && !account.remembersLogin)
        await login(account, remember: true)
        #expect(defaults.bool(forKey: scope.rememberKey) && defaults.bool(forKey: AccountController.rememberKey))
        account.deactivateForBackendChange()
        #expect(account.session == nil && !account.isRestoring && account.remembersLogin)
        #expect(defaults.bool(forKey: scope.rememberKey) && vault.calls == ["save:interactive"])
    }

    @Test func backendDeactivationRejectsLateRestoration() async {
        let gate = DispatchSemaphore(value: 0)
        let vault = LoginTestVault(stored: LoginTestVault.session(), readGate: gate)
        let (account, defaults) = setup(remember: true, vault: vault)
        let task = Task { await account.restore() }
        while !vault.calls.contains("read") { await Task.yield() }
        account.deactivateForBackendChange(); gate.signal(); await task.value
        #expect(account.session == nil && !account.isRestoring && !account.isOffline)
        #expect(defaults.bool(forKey: AccountController.rememberKey) && vault.calls == ["read"])
        #expect(LoginTestProtocol.state.paths.isEmpty)
    }
}

private final class LoginTestVault: SessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AccountSession?
    private var operations: [String] = []
    private let fails: Set<String>
    private let readGate: DispatchSemaphore?
    var calls: [String] { lock.withLock { operations } }
    init(stored: AccountSession? = nil, fails: Set<String> = [], readGate: DispatchSemaphore? = nil) {
        self.stored = stored; self.fails = fails; self.readGate = readGate
    }
    static func session(expired: Bool = false) -> AccountSession {
        .init(user: .init(id: "fixture-user", email: "fixture@example.invalid", timezone: "Asia/Shanghai", createdAt: .distantPast),
              token: "stored-fixture-session", expiresAt: expired ? .distantPast : .distantFuture)
    }
    func read() throws -> AccountSession? {
        lock.withLock { operations.append("read") }; readGate?.wait()
        return try lock.withLock { if fails.contains("read") { throw denied }; return stored }
    }
    func save(_ session: AccountSession, allowInteraction: Bool) throws {
        try lock.withLock {
            operations.append(allowInteraction ? "save:interactive" : "save:silent")
            if fails.contains("save") { throw denied }; stored = session
        }
    }
    func clear() throws {
        try lock.withLock { operations.append("clear"); if fails.contains("clear") { throw denied }; stored = nil }
    }
    private var denied: APIError { .init(code: "keychain_denied", message: "测试拒绝") }
}

private final class LoginTestProtocol: URLProtocol, @unchecked Sendable {
    static let state = LoginTestResponses()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, json) = Self.state.response(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class LoginTestResponses: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String] = []
    private var failure: String?
    var paths: [String] { lock.withLock { requests } }
    func reset() { lock.withLock { requests = []; failure = nil } }
    func setFailure(_ path: String) { lock.withLock { failure = path } }
    func response(_ request: URLRequest) -> (Int, String) {
        lock.withLock {
            let path = request.url!.path; requests.append(path)
            if path == "/private" || (failure == path && path == "/v1/me") {
                return (401, #"{"error":{"code":"unauthenticated","message":"测试会话过期"}}"#)
            }
            if failure == path { return (503, #"{"error":{"code":"unavailable","message":"测试服务失败"}}"#) }
            let timezone = request.httpMethod == "PATCH" ? "America/New_York" : "Asia/Shanghai"
            let user = "{\"id\":\"fixture-user\",\"email\":\"fixture@example.invalid\",\"timezone\":\"\(timezone)\",\"created_at\":\"2026-10-29T00:00:00Z\"}"
            if path == "/v1/me" { return (200, "{\"data\":\(user)}") }
            if path == "/v1/auth/logout" { return (200, #"{"data":{"logged_out":true}}"#) }
            return (200, "{\"data\":{\"user\":\(user),\"token\":\"fixture-session\",\"expires_at\":\"2099-12-31T00:00:00Z\"}}")
        }
    }
}
