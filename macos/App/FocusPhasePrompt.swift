import AppKit

@MainActor
final class FocusPhasePrompt {
    private let window: NSWindow
    private let showWindow: () -> Void
    private let onError: (String) -> Void
    private weak var currentFocus: FocusCoordinator?
    private var activeID: String?
    private var lastPresentedID: String?
    private(set) var alert: NSAlert?

    init(window: NSWindow, showWindow: @escaping () -> Void, onError: @escaping (String) -> Void) {
        self.window = window; self.showWindow = showWindow; self.onError = onError
    }
    func update(focus: FocusCoordinator?) {
        currentFocus = focus
        let id = focus?.snapshot?.phaseConfirmationID
        if let activeID, activeID != id { dismiss() }
        guard let focus, let snapshot = focus.snapshot, let id, id != lastPresentedID else {
            if id == nil { lastPresentedID = nil }
            return
        }
        guard window.attachedSheet == nil else { return }
        // 先显示主窗口，关闭窗口或切换到其他应用时也能看到阶段选择。
        showWindow()
        let alert = NSAlert()
        alert.messageText = snapshot.phase == .rest ? "休息结束，继续下一轮专注？" : "这一轮专注结束，是否继续？"
        alert.informativeText = snapshot.pendingPhase == .rest
            ? "第 \(snapshot.round) 轮专注已完成。开始休息后计时；等待期间保持暂停。"
            : "确认后开始第 \(snapshot.round + 1) 轮专注；等待期间保持暂停。"
        alert.addButton(withTitle: snapshot.continueTitle)
        alert.addButton(withTitle: "稍后继续")
        alert.addButton(withTitle: "结束并保存")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        self.alert = alert; activeID = id; lastPresentedID = id
        alert.beginSheetModal(for: window) { [weak self, weak focus] response in
            guard let self, self.activeID == id else { return }
            self.alert = nil; self.activeID = nil
            guard let focus, self.currentFocus === focus, focus.snapshot?.phaseConfirmationID == id else { return }
            do {
                if response == .alertFirstButtonReturn { try focus.confirmPhase(id: id) }
                else if response == .alertThirdButtonReturn { try focus.confirmPhase(id: id, finish: true) }
            } catch { self.onError(error.localizedDescription) }
        }
    }
    func dismiss() {
        guard let alert else { return }
        self.alert = nil; activeID = nil
        window.endSheet(alert.window, returnCode: .abort)
    }
}
