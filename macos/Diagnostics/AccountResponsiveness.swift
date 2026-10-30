import Foundation

private final class WaitingVault: SessionVault, @unchecked Sendable {
    let gate = DispatchSemaphore(value: 0)
    func read() throws -> AccountSession? {
        _ = gate.wait(timeout: .now() + 2)
        return nil
    }
    func save(_ session: AccountSession) throws {}
    func clear() throws {}
}

@main
struct AccountResponsiveness {
    @MainActor static func main() async throws {
        let vault = WaitingVault()
        let controller = AccountController(client: nil, vault: vault)
        let started = ContinuousClock.now
        let restore = Task { await controller.restore() }
        try await Task.sleep(for: .milliseconds(150))
        let elapsed = ContinuousClock.now - started
        guard elapsed < .seconds(1), controller.isRestoring else {
            throw APIError(code: "acceptance", message: "等待钥匙串时主线程被阻塞。")
        }
        vault.gate.signal()
        await restore.value
        guard !controller.isRestoring, controller.user == nil else {
            throw APIError(code: "acceptance", message: "钥匙串等待结束后状态未恢复。")
        }
        print("PASS：钥匙串读取等待期间主线程仍可运行，结束后恢复状态正确。")
    }
}
