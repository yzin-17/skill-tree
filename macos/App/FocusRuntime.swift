import AppKit

enum AtlasFormat {
    static func xpForecast(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return value % 60 == 0 ? "预估 +\(value / 60) XP" : "预估 +\(value / 60)–\(value / 60 + 1) XP"
    }
    static func duration(_ seconds: Int) -> String { duration(Int64(seconds)) }
    static func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return value >= 3600 ? String(format: "%02d:%02d:%02d", value / 3600, value % 3600 / 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
    static func duration(_ seconds: Int64) -> String {
        if seconds >= 3600 { return "\(seconds / 3600) 小时 \(seconds % 3600 / 60) 分钟" }
        if seconds >= 60 { return "\(seconds / 60) 分 \(seconds % 60) 秒" }
        return "\(seconds) 秒"
    }
}

@MainActor
final class FocusRuntime: NSObject, NSMenuDelegate {
    private let store: ApplicationStore
    private let showWindow: () -> Void
    private let phasePrompt: FocusPhasePrompt
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var ticks = 0
    init(store: ApplicationStore, window: NSWindow, showWindow: @escaping () -> Void) {
        self.store = store; self.showWindow = showWindow
        phasePrompt = FocusPhasePrompt(window: window, showWindow: showWindow, onError: { [weak store] message in
            store?.localError = message; store?.destination = .focus; showWindow()
        })
        super.init()
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        item.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Skill Atlas 专注")
        item.button?.imagePosition = .imageLeading
        item.button?.font = Self.timerFont
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        store.onFocusSignals = { [weak self] _ in self?.update() }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common); update(); menuWillOpen(menu)
    }
    static var timerFont: NSFont { .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular) }
    func stop() {
        phasePrompt.dismiss()
        timer?.invalidate(); timer = nil; NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        NSStatusBar.system.removeStatusItem(item)
    }
    private func tick() {
        store.focus?.tick(); update(); ticks += 1
        if ticks % 15 == 0 { Task { await store.sync?.synchronize() } }
    }
    private func update() {
        let current = store.focus?.snapshot
        if current?.status == .running && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "保存正在进行的专注计时")
        } else if current?.status != .running, let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        if let current {
            let seconds = current.remainingSeconds ?? current.effectiveSeconds
            let state = current.pendingPhase != nil ? "确认" : current.status == .paused ? "暂停" : current.phase == .rest ? "休息" : "专注"
            item.button?.title = " \(AtlasFormat.clock(seconds)) · \(state)"
        } else { item.button?.title = "" }
        let hint = current?.pendingPhase != nil ? "等待确认：\(current!.continueTitle)" : current?.status == .paused ? "专注已暂停" : current == nil ? "开始一次专注" : "专注持续运行"
        item.button?.toolTip = "Skill Atlas · \(hint)"
        phasePrompt.update(focus: store.focus)
    }
    func menuWillOpen(_ menu: NSMenu) {
        update(); menu.removeAllItems()
        add(menu, "打开 Skill Atlas", #selector(openWindow))
        menu.addItem(.separator())
        if let focus = store.focus?.snapshot {
            let skill = store.library.skills.first { $0.id == focus.skillId }?.name ?? "当前技能"
            let title = NSMenuItem(title: "\(skill) · 有效 \(AtlasFormat.duration(Int64(focus.effectiveSeconds)))", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
            add(menu, focus.status == .running ? "暂停专注" : focus.continueTitle, #selector(togglePause))
            add(menu, "结束并保存", #selector(finish))
        } else { add(menu, "开始专注…", #selector(openFocus)) }
        if let sync = store.sync, sync.pendingCount + sync.activityCount > 0 {
            let pending = NSMenuItem(title: "\(sync.pendingCount) 条专注待同步", action: nil, keyEquivalent: ""); pending.isEnabled = false; menu.addItem(pending)
            add(menu, "立即重试同步", #selector(synchronize))
        }
        menu.addItem(.separator()); add(menu, "退出 Skill Atlas", #selector(quit), key: "q")
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") { let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry) }
    @objc private func openWindow() { showWindow() }
    @objc private func openFocus() { store.destination = .focus; showWindow() }
    @objc func togglePause() {
        do { if store.focus?.snapshot?.status == .running { try store.focus?.pause() } else { try store.focus?.resume() }; update() }
        catch { store.localError = error.localizedDescription; showWindow() }
    }
    @objc func finish() { do { try store.focus?.finish(); update() } catch { store.localError = error.localizedDescription; showWindow() } }
    @objc private func synchronize() { Task { await store.sync?.synchronize(force: true) } }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func willSleep() { do { try store.focus?.handle(.willSleep); update() } catch { store.localError = error.localizedDescription } }
}
