import Foundation

@MainActor
struct BackendRuntime {
    let account: AccountController
    let library: SkillLibrary
    let tasks: TaskLibrary
    let achievements: AchievementLibrary
    let local: LocalFocusStore?
    let focus: FocusCoordinator?
    let sync: FocusSynchronizer?
    let error: String?

    init(client: APIClient?, scope: BackendScope?, root: URL?) {
        let account = AccountController(client: client,
            vault: KeychainSessionVault(service: scope?.vaultService ?? "local.skillatlas.session"),
            rememberKey: scope?.rememberKey ?? AccountController.rememberKey)
        self.account = account
        var database: LocalFocusStore?
        var coordinator: FocusCoordinator?
        var failure: String?
        do {
            guard let root else { throw APIError(code: "local_store", message: "本机存储位置不可用。") }
            let directory = scope?.directory(in: root) ?? root
            let store = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
            database = store; coordinator = try FocusCoordinator(store: store)
        } catch { failure = "本机记录无法打开，专注暂不可用：\(error.localizedDescription)" }
        local = database; focus = coordinator; error = failure
        library = SkillLibrary(client: client, account: account, local: database)
        tasks = TaskLibrary(account: account, local: database)
        achievements = AchievementLibrary(account: account, local: database)
        if let database, let client {
            sync = FocusSynchronizer(local: database, remote: client, identity: {
                guard !account.isBusy, let session = account.session else { return nil }
                return SyncIdentity(accountId: session.user.id, token: session.token)
            })
        } else { sync = nil }
    }
}
