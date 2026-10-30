import SwiftUI

@MainActor @Observable
final class ApplicationStore {
    var health: Health?
    var connectionError: String?
    var isChecking = false
    private(set) var client: APIClient?
    private(set) var account: AccountController
    private(set) var library: SkillLibrary
    private(set) var tasks: TaskLibrary
    private(set) var achievements: AchievementLibrary
    private(set) var local: LocalFocusStore?
    private(set) var focus: FocusCoordinator?
    private(set) var sync: FocusSynchronizer?
    private(set) var backendAddress: BackendAddress?
    var backendIdentity: String { backendAddress?.text ?? "missing" }
    var defaultBackendAddress: String { backendEnvironment?.defaultAddress.text ?? "" }
    var isBackendEditorPresented = false
    @ObservationIgnored var onFocusSignals: (([FocusSignal]) -> Void)?
    @ObservationIgnored private let backendEnvironment: BackendEnvironment?
    @ObservationIgnored private let backendPreferences: BackendPreferences?
    @ObservationIgnored private let rootDirectory: URL?
    let notifications = FocusNotifications()
    var localError: String?
    var destination: Destination = .overview
    var requestedTaskId: String?
    var requestedSkillId: String?

    init() {
        var environment: BackendEnvironment?
        var preferences: BackendPreferences?
        var address: BackendAddress?
        var connection: APIClient?
        do {
            let value = try BackendEnvironment.bundled()
            let settings = BackendPreferences(defaultAddress: value.defaultAddress)
            environment = value; preferences = settings; address = settings.current
            connection = value.client(for: settings.current)
        } catch { connectionError = error.localizedDescription }
        backendEnvironment = environment; backendPreferences = preferences; backendAddress = address; client = connection
        rootDirectory = Self.dataRoot()
        let scope = address.flatMap { address in environment.map { BackendScope(address: address, defaultAddress: $0.defaultAddress) } }
        let runtime = BackendRuntime(client: connection, scope: scope, root: rootDirectory)
        account = runtime.account; library = runtime.library; tasks = runtime.tasks; achievements = runtime.achievements
        local = runtime.local; focus = runtime.focus; sync = runtime.sync; localError = runtime.error
        wireRuntime()
    }

    private static func dataRoot() -> URL? {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["SKILLATLAS_DATA_DIR"] { return URL(fileURLWithPath: path, isDirectory: true) }
        #endif
        return try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("SkillAtlas", isDirectory: true)
    }

    private func wireRuntime() {
        let identity = account
        let coordinator = focus
        account.beforeSignOut = { [weak coordinator] in try coordinator?.pause() }
        coordinator?.onSignals = { [weak self, weak coordinator] signals in
            guard let self, self.focus === coordinator else { return }
            self.notifications.receive(signals); self.onFocusSignals?(signals)
        }
        coordinator?.onPendingChange = { [weak self, weak coordinator, weak identity] in
            guard let self, let identity, self.focus === coordinator, self.account === identity else { return }
            do { try self.sync?.reload() } catch { self.localError = error.localizedDescription }
            let sync = self.sync
            Task { guard self.account === identity else { return }; await sync?.synchronize() }
        }
        sync?.onAuthenticationFailure = { [weak self, weak identity] owner in
            guard let self, let identity, self.account === identity, self.account.user?.id == owner else { return }
            do { try self.account.expireSession() } catch { self.localError = error.localizedDescription }
        }
    }

    func probeClient(for address: BackendAddress) throws -> APIClient {
        guard let backendEnvironment else { throw APIError(code: "configuration_missing", message: "连接配置缺失，请重新构建应用。") }
        return backendEnvironment.client(for: address)
    }

    func changeBackend(to input: String) throws {
        let address = try BackendAddress(input)
        guard address != backendAddress else { isBackendEditorPresented = false; return }
        guard !account.isBusy else { throw APIError(code: "account_busy", message: "请等待账号操作完成后重试。") }
        guard let backendEnvironment, let backendPreferences else { throw APIError(code: "configuration_missing", message: "连接配置缺失，请重新构建应用。") }
        try focus?.pause()
        let connection = backendEnvironment.client(for: address)
        let scope = BackendScope(address: address, defaultAddress: backendEnvironment.defaultAddress)
        let runtime = BackendRuntime(client: connection, scope: scope, root: rootDirectory)
        if let error = runtime.error { throw APIError(code: "local_store", message: error) }
        focus?.onPendingChange = nil; focus?.onSignals = nil; sync?.onAuthenticationFailure = nil
        account.deactivateForBackendChange(); client?.invalidate()
        backendPreferences.save(address)
        client = connection; account = runtime.account; library = runtime.library; tasks = runtime.tasks
        achievements = runtime.achievements; local = runtime.local; focus = runtime.focus; sync = runtime.sync
        health = nil; connectionError = nil; isChecking = false; localError = nil
        destination = .overview; requestedTaskId = nil; requestedSkillId = nil; isBackendEditorPresented = false
        backendAddress = address
        wireRuntime()
    }

    func activateAccount() async {
        destination = .overview; requestedTaskId = nil; requestedSkillId = nil
        library.clear(); tasks.clear(); achievements.clear()
        do {
            try focus?.activate(accountId: account.user?.id)
            try sync?.activate(); try library.restoreCache(); try tasks.restoreCache()
            try achievements.restore()
        } catch { localError = error.localizedDescription }
        guard account.user != nil else { return }
        await refreshWorkspace()
    }
    func refreshWorkspace() async {
        let library = self.library, tasks = self.tasks, achievements = self.achievements, sync = self.sync
        async let skills: Void = library.refresh()
        async let taskList: Void = tasks.refresh()
        async let upload: Void = sync?.synchronize(force: true) ?? ()
        async let achievementList: Void = achievements.refresh()
        _ = await (skills, taskList, upload, achievementList)
    }
    func openTask(_ id: String) { requestedTaskId = id; destination = .tasks }
    func openSkill(_ id: String) { requestedSkillId = id; destination = .skills }
    func prepareFocus(skillId: String? = nil, taskId: String? = nil) { requestedSkillId = skillId; requestedTaskId = taskId; destination = .focus }

    func checkConnection() async {
        guard let client else { return }
        isChecking = true
        defer { if self.client === client { isChecking = false } }
        do {
            let value = try await client.checkHealth()
            guard self.client === client else { return }
            health = value
            connectionError = nil
        } catch {
            guard self.client === client else { return }
            health = nil
            connectionError = BackendConnectionCheck.message(error)
        }
    }
}
