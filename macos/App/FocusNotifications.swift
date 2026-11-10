import AppKit
import Observation
import UserNotifications

struct FocusNotificationSettings {
    var authorization: UNAuthorizationStatus
    var alert: UNNotificationSetting
}

@MainActor
protocol FocusNotificationDelivery {
    func settings() async -> FocusNotificationSettings
    func requestAuthorization() async throws
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
final class SystemFocusNotificationDelivery: NSObject, FocusNotificationDelivery, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self }
    func settings() async -> FocusNotificationSettings {
        let value = await center.notificationSettings()
        return .init(authorization: value.authorizationStatus, alert: value.alertSetting)
    }
    func requestAuthorization() async throws { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }
}

@MainActor @Observable
final class FocusNotifications {
    private(set) var status = "开始限时专注时将申请系统通知权限"
    private(set) var enabled: Bool
    private(set) var soundEnabled: Bool
    private(set) var needsSystemSettings = false
    private let delivery: any FocusNotificationDelivery
    private let preferences: UserDefaults
    private let playSound: () -> Void
    private var lastReminderID: String?
    private var requestingAuthorization = false

    init(preferences: UserDefaults = .standard, delivery: (any FocusNotificationDelivery)? = nil,
         playSound: @escaping () -> Void = {
             if NSSound(named: NSSound.Name("Glass"))?.play() != true { NSSound.beep() }
         }) {
        self.preferences = preferences
        self.delivery = delivery ?? SystemFocusNotificationDelivery()
        self.playSound = playSound
        enabled = preferences.object(forKey: "focusNotificationsEnabled") as? Bool ?? true
        soundEnabled = preferences.object(forKey: "focusSoundEnabled") as? Bool ?? true
        Task { await refresh() }
    }

    func refresh() async {
        let settings = await delivery.settings()
        let authorized = settings.authorization == .authorized || settings.authorization == .provisional
        needsSystemSettings = enabled && (settings.authorization == .denied || (authorized && settings.alert == .disabled))
        guard enabled else { status = "系统横幅已关闭"; return }
        switch settings.authorization {
        case .authorized, .provisional:
            status = settings.alert == .disabled ? "系统横幅已关闭，请在通知设置中开启" : "系统横幅已开启"
        case .denied: status = "系统通知未允许，可在通知设置中开启"
        default: status = "开始限时专注时将申请系统通知权限"
        }
    }
    func enable() async {
        enabled = true; preferences.set(true, forKey: "focusNotificationsEnabled")
        await prepareForTimedSession()
    }
    func disable() {
        enabled = false; preferences.set(false, forKey: "focusNotificationsEnabled")
        needsSystemSettings = false; status = "系统横幅已关闭"
    }
    func setSoundEnabled(_ value: Bool) { soundEnabled = value; preferences.set(value, forKey: "focusSoundEnabled") }
    func previewSound() { playSound() }
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    private func prepareForTimedSession() async {
        guard enabled, !requestingAuthorization else { return }
        requestingAuthorization = true
        defer { requestingAuthorization = false }
        do {
            let settings = await delivery.settings()
            if enabled && settings.authorization == .notDetermined { try await delivery.requestAuthorization() }
            await refresh()
        } catch { if enabled { status = "无法开启系统通知：\(error.localizedDescription)" } }
    }

    func receive(_ signals: [FocusSignal]) {
        if enabled && signals.contains(where: { [.started, .resumed].contains($0.kind) && $0.mode != .countUp }) {
            Task { await prepareForTimedSession() }
        }
        guard let signal = signals.last(where: { [.finished, .phaseEnded].contains($0.kind) }) else { return }
        let identifier = signal.kind == .finished ? "focus-finished-\(signal.sessionId)" : signal.id
        guard identifier != lastReminderID else { return }
        lastReminderID = identifier
        if soundEnabled { playSound() }
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        switch signal.kind {
        case .finished: content.title = "专注已保存"; content.body = "这次有效专注 \(AtlasFormat.duration(signal.effectiveSeconds))。"
        default:
            content.title = signal.phase == .rest ? "休息已结束" : "这一轮专注已结束"
            content.body = "请在阶段确认弹窗中选择是否继续；等待期间保持暂停。"
        }
        // 声音由应用统一播放，不依赖系统通知授权，也不会与横幅声音重叠。
        content.sound = nil
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task {
            await refresh()
            guard enabled, !needsSystemSettings else { return }
            do { try await delivery.add(request) }
            catch { if enabled { status = "系统通知发送失败：\(error.localizedDescription)" } }
        }
    }
}
