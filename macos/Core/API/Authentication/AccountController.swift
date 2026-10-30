import Foundation
import Observation

@MainActor @Observable
final class AccountController {
    private(set) var session: AccountSession?
    var user: AccountUser? { session?.user }
    var token: String? { session?.token }
    private(set) var isBusy = false
    private(set) var isRestoring = true
    private(set) var isOffline = false
    var errorMessage: String?
    var sessionNotice: String?
    private(set) var remembersLogin: Bool
    var beforeSignOut: (() throws -> Void)?
    private let client: APIClient?
    private let vault: any SessionVault
    private let preferences: UserDefaults
    private let preferenceKey: String
    private var restoreGeneration = UUID()
    private var preferenceGeneration = UUID()
    static let rememberKey = "account.rememberLogin"

    init(client: APIClient?, vault: any SessionVault = KeychainSessionVault(), preferences: UserDefaults = .standard,
         rememberKey: String = AccountController.rememberKey) {
        self.client = client; self.vault = vault; self.preferences = preferences
        self.preferenceKey = rememberKey
        remembersLogin = preferences.bool(forKey: rememberKey)
    }

    private func remember(_ enabled: Bool) {
        remembersLogin = enabled
        preferences.set(enabled, forKey: preferenceKey)
    }

    func usePasswordLogin() {
        restoreGeneration = UUID()
        preferenceGeneration = UUID()
        remember(false); isRestoring = false; errorMessage = nil
    }

    func deactivateForBackendChange() {
        restoreGeneration = UUID(); preferenceGeneration = UUID()
        session = nil; isRestoring = false; isOffline = false
        errorMessage = nil; sessionNotice = nil
    }

    func restore() async {
        let generation = UUID(); restoreGeneration = generation
        defer { if generation == restoreGeneration { isRestoring = false } }
        guard remembersLogin else { return }
        do {
            let vault = self.vault
            let stored = try await Task.detached(priority: .userInitiated, operation: { try vault.read() }).value
            guard generation == restoreGeneration, !Task.isCancelled else { return }
            guard var saved = stored, saved.expiresAt > .now else { remember(false); try? vault.clear(); return }
            guard let client else { session = saved; isOffline = true; return }
            do {
                saved.user = try await client.request("/v1/me", token: saved.token)
                guard generation == restoreGeneration, !Task.isCancelled else { return }
                session = saved; isOffline = false
            } catch let error as APIError where error.code == "unauthenticated" {
                guard generation == restoreGeneration else { return }
                remember(false); try? vault.clear(); session = nil
            } catch {
                guard generation == restoreGeneration, !Task.isCancelled else { return }
                session = saved; isOffline = true
            }
        } catch {
            guard generation == restoreGeneration else { return }
            remember(false); errorMessage = "无法恢复登录，请输入账号密码。"
        }
    }

    func authenticate(email: String, password: String, create: Bool, rememberLogin: Bool = false) async {
        guard let client, !isBusy else { return }
        restoreGeneration = UUID(); isRestoring = false
        preferenceGeneration = UUID()
        isBusy = true; errorMessage = nil; sessionNotice = nil
        defer { isBusy = false }
        do {
            let input = AccountCredentials(email: email, password: password, timezone: create ? TimeZone.current.identifier : nil)
            let newSession: AccountSession = try await client.request(create ? "/v1/auth/register" : "/v1/auth/login", method: "POST", body: JSONEncoder().encode(input))
            session = newSession; isOffline = false
            remember(false)
            if rememberLogin { await persist(newSession, allowInteraction: true) }
        } catch { errorMessage = (error as? APIError)?.message ?? "无法连接后端，请检查连接后重试。" }
    }

    private func persist(_ saved: AccountSession, allowInteraction: Bool) async {
        let vault = self.vault
        let generation = preferenceGeneration
        do {
            try await Task.detached(priority: .userInitiated, operation: { try vault.save(saved, allowInteraction: allowInteraction) }).value
            guard session?.token == saved.token, generation == preferenceGeneration else { return }
            remember(true)
        } catch {
            guard session?.token == saved.token, generation == preferenceGeneration else { return }
            remember(false); sessionNotice = "已登录，本次登录未保存。"
        }
    }

    func stopRemembering() async {
        let wasRemembered = remembersLogin
        preferenceGeneration = UUID()
        remember(false)
        if wasRemembered { let vault = self.vault; try? await Task.detached { try vault.clear() }.value }
    }

    func signOut() async {
        guard let client, let session, !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            try beforeSignOut?()
            let _: LogoutResult = try await client.request("/v1/auth/logout", method: "POST", token: session.token)
            let wasRemembered = remembersLogin
            remember(false); self.session = nil; isOffline = false; sessionNotice = nil
            if wasRemembered { let vault = self.vault; try? await Task.detached { try vault.clear() }.value }
        } catch { errorMessage = "退出尚未完成。请确认后端连接后重试；本地记录已保留。" }
    }

    func expireSession() throws {
        try beforeSignOut?()
        let wasRemembered = remembersLogin
        remember(false); session = nil; sessionNotice = nil; isOffline = false
        if wasRemembered { try? vault.clear() }
    }

    func updateTimezone(_ timezone: String) async throws {
        struct Input: Encodable { let timezone: String }
        guard let current = session else { throw FocusEngineError.invalidIdentity }
        let user: AccountUser = try await request("/v1/me", method: "PATCH", body: APIClient.body(Input(timezone: timezone)))
        guard session?.token == current.token else { throw CancellationError() }
        var updated = current; updated.user = user
        session = updated
        if remembersLogin { await persist(updated, allowInteraction: false) }
    }

    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let client, let session else { throw APIError(code: "unauthenticated", message: "请先登录。") }
        do {
            let value: T = try await client.request(path, method: method, token: session.token, body: body)
            guard self.session?.token == session.token else { throw CancellationError() }
            isOffline = false; return value
        } catch let error as APIError where error.code == "unauthenticated" {
            if self.session?.token == session.token { try expireSession() }
            throw error
        } catch {
            if self.session?.token == session.token, error is URLError { isOffline = true }
            throw error
        }
    }
}
