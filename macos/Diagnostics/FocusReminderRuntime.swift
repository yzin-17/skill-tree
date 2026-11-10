import AppKit
import UserNotifications

@MainActor
private final class ReminderDeliveryProbe: FocusNotificationDelivery {
    var current = FocusNotificationSettings(authorization: .authorized, alert: .enabled)
    var requests: [UNNotificationRequest] = []
    var permissionRequests = 0
    var failure = false
    var permissionFailure = false
    func settings() async -> FocusNotificationSettings { current }
    func requestAuthorization() async throws {
        permissionRequests += 1
        if permissionFailure { throw CocoaError(.fileReadUnknown) }
        current.authorization = .authorized
    }
    func add(_ request: UNNotificationRequest) async throws {
        if failure { throw CocoaError(.fileWriteUnknown) }
        requests.append(request)
    }
}

@main
struct FocusReminderRuntime {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { print("失败：\(error.localizedDescription)"); exit(1) }
        }
        app.run()
    }
    @MainActor private static func run() async throws {
        let suite = "focus-reminder-diagnostic-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let delivery = ReminderDeliveryProbe()
        var sounds = 0
        let notifications = FocusNotifications(preferences: preferences, delivery: delivery, playSound: { sounds += 1 })
        try require(notifications.soundEnabled && notifications.enabled, "首次使用未默认开启提醒")

        let local = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
        let base = Date.now
        var elapsed: TimeInterval = 0
        let focus = try FocusCoordinator(store: local, clock: { .init(monotonic: elapsed, wall: base.addingTimeInterval(elapsed)) })
        try focus.activate(accountId: UUID().uuidString)
        var latestSignals: [FocusSignal] = []
        focus.onSignals = { signals in latestSignals = signals; notifications.receive(signals) }
        let skill = UUID().uuidString
        try focus.start(skillId: skill, configuration: .init(mode: .pomodoro, targetSeconds: 2, restSeconds: 1, rounds: 2))
        await settle()
        try require(sounds == 0 && delivery.requests.isEmpty, "开始专注时提前响铃")
        elapsed = 2; focus.tick(); await settle()
        try require(sounds == 1 && delivery.requests.last?.content.title == "这一轮专注已结束", "专注结束未提醒")
        try require(focus.snapshot?.pendingPhase == .rest && focus.snapshot?.status == .paused, "未等待确认休息")
        try focus.pause(); elapsed = 20; focus.tick(); await settle()
        try require(sounds == 1, "暂停期间错误提醒")
        try focus.resume(); elapsed = 21; focus.tick(); await settle()
        try require(sounds == 2 && delivery.requests.last?.content.title == "休息已结束", "休息结束未提醒")
        try require(focus.snapshot?.pendingPhase == .focus, "未等待确认下一轮专注")
        try focus.resume(); await settle()
        try require(sounds == 2, "确认继续时重复响铃")
        elapsed = 23; focus.tick(); await settle()
        try require(sounds == 3 && delivery.requests.last?.content.title == "专注已保存", "最后一轮完成未提醒")
        try require(focus.snapshot == nil && focus.lastFinished?.submission.effectiveSeconds == 4, "提醒改变了计时保存")
        try require(delivery.requests.allSatisfy { $0.content.sound == nil }, "系统与应用重复播放声音")
        try require(delivery.requests.last?.identifier == "focus-finished-\(focus.lastFinished!.submission.id)", "完成通知未按会话去重")
        notifications.receive(latestSignals); await settle()
        try require(sounds == 3 && delivery.requests.count == 3, "同一完成信号重复提醒")

        // 迟到的观察停在首个阶段结束点，等待用户确认。
        try focus.start(skillId: skill, configuration: .init(mode: .pomodoro, targetSeconds: 2, restSeconds: 1, rounds: 2))
        elapsed = 100; focus.tick(); await settle()
        try require(sounds == 4 && delivery.requests.count == 4 && focus.snapshot?.pendingPhase == .rest, "迟到观察未停在首个阶段边界")
        try require(focus.snapshot?.effectiveSeconds == 2, "等待确认期间计入额外专注")
        try focus.finish(); await settle()

        notifications.disable()
        try focus.start(skillId: skill, configuration: .init(mode: .countdown, targetSeconds: 1))
        elapsed = 101; focus.tick(); await settle()
        try require(sounds == 6 && delivery.requests.count == 5, "关闭系统横幅后声音不可用")
        notifications.setSoundEnabled(false)
        try focus.start(skillId: skill, configuration: .init(mode: .countdown, targetSeconds: 1))
        elapsed = 102; focus.tick(); await settle()
        try require(sounds == 6 && delivery.requests.count == 5, "关闭全部提醒后仍提醒")
        let restored = FocusNotifications(preferences: preferences, delivery: delivery, playSound: {})
        try require(!restored.enabled && !restored.soundEnabled, "未保留关闭选择")

        // 旧版显式关闭横幅的偏好仍然保留，新声音开关默认开启。
        preferences.removeObject(forKey: "focusSoundEnabled")
        let migrated = FocusNotifications(preferences: preferences, delivery: delivery, playSound: {})
        try require(!migrated.enabled && migrated.soundEnabled, "旧版偏好迁移错误")
        delivery.current.authorization = .notDetermined
        await notifications.enable()
        try require(delivery.permissionRequests == 1 && notifications.status == "系统横幅已开启", "未申请系统授权")
        delivery.current.authorization = .denied
        notifications.setSoundEnabled(true)
        try focus.start(skillId: skill, configuration: .init(mode: .countdown, targetSeconds: 1))
        elapsed = 103; focus.tick(); await settle()
        try require(sounds == 7 && delivery.requests.count == 5 && notifications.needsSystemSettings, "拒绝授权未保留声音或缺少提示")
        try require(delivery.permissionRequests == 1, "拒绝后重复申请授权")

        delivery.current = .init(authorization: .authorized, alert: .disabled)
        await notifications.refresh()
        try require(notifications.needsSystemSettings && notifications.status.contains("横幅已关闭"), "关闭横幅后状态不准确")
        delivery.current.alert = .enabled; delivery.failure = true
        try focus.start(skillId: skill, configuration: .init(mode: .countdown, targetSeconds: 1))
        elapsed = 104; focus.tick(); await settle()
        try require(sounds == 8 && notifications.status.contains("发送失败"), "投递失败未显示状态")
        try require(focus.snapshot == nil && focus.lastFinished?.submission.effectiveSeconds == 1, "通知失败影响保存")

        delivery.current.authorization = .notDetermined; delivery.permissionFailure = true
        await notifications.enable()
        try require(notifications.status.contains("无法开启系统通知"), "授权失败未显示状态")
        delivery.permissionFailure = false
        preferences.removeObject(forKey: "focusNotificationsEnabled")
        let firstUse = FocusNotifications(preferences: preferences, delivery: delivery, playSound: {})
        firstUse.receive([FocusSignal(id: UUID().uuidString, kind: .started, sessionId: UUID().uuidString,
            accountId: UUID().uuidString, skillId: skill, taskId: nil, occurredAt: .now,
            effectiveSeconds: 0, mode: .pomodoro, phase: .focus, round: 1)])
        await settle()
        try require(delivery.current.authorization == .authorized, "首次限时专注没有自动请求授权")
        print("通过：真实协调器的阶段结束提醒、确认继续、完成去重、迟到观察、开关持久化、旧版设置、授权与投递失败。")

        notifications.disable(); notifications.setSoundEnabled(false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Skill Atlas 阶段确认诊断"
        window.isReleasedWhenClosed = false
        var shown = 0
        var promptErrors: [String] = []
        let prompt = FocusPhasePrompt(window: window, showWindow: {
            shown += 1; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }, onError: { promptErrors.append($0) })
        defer { prompt.dismiss(); window.orderOut(nil) }
        try focus.start(skillId: skill, configuration: .init(mode: .pomodoro, targetSeconds: 2, restSeconds: 1, rounds: 2))
        elapsed = 106; focus.tick(); prompt.update(focus: focus); await settle()
        let restAlert = try required(prompt.alert, "没有弹出阶段确认框")
        try require(window.isVisible && shown == 1, "主窗口关闭时未显示阶段弹窗")
        try require(restAlert.buttons.map(\.title) == ["开始休息", "稍后继续", "结束并保存"], "专注结束的弹窗按钮错误")
        try require(window.attachedSheet === restAlert.window, "原生阶段确认未附加到主窗口")
        restAlert.buttons[1].performClick(nil); await settle()
        try require(focus.snapshot?.pendingPhase == .rest && focus.snapshot?.status == .paused, "稍后继续没有保留暂停")
        prompt.update(focus: focus)
        try require(prompt.alert == nil && shown == 1, "稍后继续后重复弹窗")
        try focus.confirmPhase(id: focus.snapshot!.phaseConfirmationID!); prompt.update(focus: focus)
        elapsed = 107; focus.tick(); prompt.update(focus: focus); await settle()
        let focusAlert = try required(prompt.alert, "休息结束没有弹窗")
        try require(focusAlert.messageText.contains("休息结束") && focusAlert.buttons[0].title == "开始第 2 轮专注", "休息结束的弹窗内容错误")
        focusAlert.buttons[0].performClick(nil); await settle()
        try require(focus.snapshot?.phase == .focus && focus.snapshot?.round == 2 && focus.snapshot?.status == .running, "弹窗确认未开始下一轮")
        elapsed = 109; focus.tick(); prompt.update(focus: focus)
        try require(focus.snapshot == nil && prompt.alert == nil && focus.lastFinished?.submission.effectiveSeconds == 4, "最终一轮没有正确保存")

        try focus.start(skillId: skill, configuration: .init(mode: .pomodoro, targetSeconds: 2, restSeconds: 0, rounds: 2))
        elapsed = 111; focus.tick(); prompt.update(focus: focus); await settle()
        let saveAlert = try required(prompt.alert, "零休息没有确认下一轮")
        try require(saveAlert.buttons[0].title == "开始第 2 轮专注", "零休息的下一阶段错误")
        saveAlert.buttons[2].performClick(nil); await settle()
        try require(focus.snapshot == nil && focus.lastFinished?.submission.effectiveSeconds == 2, "弹窗结束并保存错误")
        prompt.update(focus: focus)
        try focus.start(skillId: skill, configuration: .init(mode: .pomodoro, targetSeconds: 2, restSeconds: 1, rounds: 2))
        elapsed = 113; focus.tick(); prompt.update(focus: focus); await settle()
        let stale = try required(prompt.alert, "过期响应测试没有创建弹窗")
        try focus.finish()
        try focus.start(skillId: skill, configuration: .init(mode: .countdown, targetSeconds: 10))
        let newID = focus.snapshot!.id
        stale.buttons[2].performClick(nil); await settle()
        try require(focus.snapshot?.id == newID && focus.snapshot?.status == .running, "旧弹窗修改了新会话")
        prompt.update(focus: focus)
        try require(promptErrors.isEmpty, "原生弹窗发生错误：\(promptErrors)")
        print("通过：实际 NSAlert 专注/休息弹窗、三个按钮、关闭窗口后显示、稍后不重复提示、零休息及过期响应隔离。")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = item.button!
        button.font = FocusRuntime.timerFont
        button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        var widths = Set<Double>()
        for seconds in 0..<3600 {
            button.title = " \(AtlasFormat.clock(seconds)) · 专注"
            widths.insert(Double(button.intrinsicContentSize.width))
        }
        try require(widths.count == 1, "菜单栏秒数导致宽度变化：\(widths)")
        let hourWidths = [3600, 3661, 3999, 7199, 86399].map { seconds in
            button.title = " \(AtlasFormat.clock(seconds)) · 暂停"
            return button.intrinsicContentSize.width
        }
        try require(Set(hourWidths).count == 1, "小时格式内菜单栏宽度变化")
        print("通过：真实 NSStatusBar 按钮 3,600 种秒数组合宽度一致；小时格式抽样宽度一致。")
        try require(NSSound(named: NSSound.Name("Glass")) != nil, "系统提示音资源不存在")
        print("通过：macOS Glass 提示音资源存在；未在诊断中实际播放声音或发送系统横幅。")
    }
    @MainActor private static func settle() async { for _ in 0..<30 { await Task.yield() } }
    private static func required<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw NSError(domain: "FocusReminderRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        return value
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "FocusReminderRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
