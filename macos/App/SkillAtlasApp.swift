import SwiftUI
import AppKit

@main
struct SkillAtlasApp: App {
    @NSApplicationDelegateAdaptor(AtlasApplicationDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("打开主窗口") { delegate.showWindow() }.keyboardShortcut("0", modifiers: .command)
                }
                CommandMenu("专注") {
                    Button("打开专注页面") { delegate.showFocusWindow() }
                        .keyboardShortcut("f", modifiers: [.command, .shift])
                    if let focus = delegate.store.focus?.snapshot {
                        Divider()
                        Text("有效专注 \(AtlasFormat.duration(focus.effectiveSeconds))")
                        Button(focus.status == .running ? "暂停专注" : "继续专注") { delegate.toggleFocus() }
                            .keyboardShortcut("p", modifiers: [.command, .shift])
                        Button("结束并保存") { delegate.finishFocus() }
                    }
                }
            }
    }
}

@MainActor
final class AtlasApplicationDelegate: NSObject, NSApplicationDelegate {
    let store = ApplicationStore()
    private var window: NSWindow?
    private var focusRuntime: FocusRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Skill Atlas"
        window.identifier = NSUserInterfaceItemIdentifier("skill-atlas-main")
        window.minSize = NSSize(width: 840, height: 560)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(white: 0.035, alpha: 1)
        window.contentView = NSHostingView(rootView: AtlasRootView().environment(store).preferredColorScheme(.dark))
        window.setFrameAutosaveName("SkillAtlasMainWindow")
        if !window.setFrameUsingName("SkillAtlasMainWindow") { window.center() }
        self.window = window
        focusRuntime = FocusRuntime(store: store) { [weak self] in self?.showWindow() }
        showWindow()
        DevelopmentCapture.schedule()
    }

    func showWindow() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func showFocusWindow() { store.destination = .focus; showWindow() }
    func toggleFocus() { focusRuntime?.togglePause() }
    func finishFocus() { focusRuntime?.finish() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do { try store.focus?.handle(.willTerminate); return .terminateNow }
        catch {
            store.localError = "当前专注尚未保存，已保留窗口，请检查本机存储后重试退出。"
            showWindow(); return .terminateCancel
        }
    }
    func applicationWillTerminate(_ notification: Notification) { focusRuntime?.stop() }
}

struct AtlasRootView: View {
    @Environment(ApplicationStore.self) private var store
    var body: some View {
        ZStack {
            if store.account.isRestoring {
                VStack(spacing: 16) {
                    ProgressView("正在读取账号")
                    Button("账号密码登录") { store.account.usePasswordLogin() }
                    Button("后端地址…") { store.isBackendEditorPresented = true }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(AtlasTheme.ground)
            } else if store.account.user == nil { AccountView() }
            else {
                VStack(spacing: 0) {
                    if let notice = store.account.sessionNotice {
                        HStack { Text(notice).font(.callout); Spacer(); Button("关闭") { store.account.sessionNotice = nil } }
                            .padding(12).background(AtlasTheme.surface)
                    }
                    WorkspaceView()
                }
            }
        }.id(store.backendIdentity).frame(minWidth: 840, minHeight: 560)
            .task(id: store.backendIdentity) { await store.account.restore() }
            .onChange(of: store.account.user?.id) { _, current in
                let account = store.account
                Task { guard store.account === account else { return }; await store.activateAccount() }
            }
            .sheet(isPresented: Binding(get: { store.isBackendEditorPresented }, set: { store.isBackendEditorPresented = $0 })) {
                BackendAddressEditor(address: store.backendAddress?.text ?? "", defaultAddress: store.defaultBackendAddress,
                                     makeClient: { try store.probeClient(for: $0) })
            }
    }
}
