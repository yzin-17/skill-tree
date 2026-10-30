import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsPage: View {
    @Environment(ApplicationStore.self) private var store
    @State private var working = false
    @State private var error: String?
    @State private var exportPath: URL?
    @State private var notice: String?
    @State private var signOut = false
    private var queueCount: Int { (store.sync?.pendingCount ?? 0) + (store.sync?.blockedCount ?? 0) + (store.sync?.activityCount ?? 0) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                PageHeading("设置")
                if let error { InlineFailure(message: error) { self.error = nil } }
                if let notice { Text(notice).font(.callout).foregroundStyle(AtlasTheme.muted) }
                ConnectionPanel()
                if let user = store.account.user {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("账号").font(.title3.weight(.semibold))
                        LabeledContent("邮箱", value: user.email)
                        HStack {
                            LabeledContent("登录状态", value: store.account.remembersLogin ? "已记住登录" : "仅本次运行")
                            if store.account.remembersLogin {
                                Button("取消记住登录") { Task { await store.account.stopRemembering() } }.disabled(store.account.isBusy)
                            }
                        }
                        Button("退出并切换账号") { signOut = true }.disabled(store.account.isBusy || working)
                        if let message = store.account.errorMessage { Text(message).font(.callout).foregroundStyle(.red) }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    Text("本机记录与同步").font(.title3.weight(.semibold))
                    HStack { Text(queueCount == 0 ? "专注与活动记录已同步" : "\(queueCount) 条专注或活动记录等待确认"); Spacer(); Button("立即同步") { Task { await store.refreshWorkspace() } }.disabled(store.sync?.isSyncing == true) }
                    if !store.tasks.commands.isEmpty || store.achievements.pending != nil { Text("\(store.tasks.commands.count) 项任务操作\(store.achievements.pending == nil ? "" : "及 1 项成就操作")待确认").font(.callout).foregroundStyle(AtlasTheme.muted) }
                    if let snapshot = store.focus?.snapshot { Text("当前专注已在本机保存：\(AtlasFormat.duration(Int(snapshot.effectiveElapsed)))，\(snapshot.status == .running ? "正在计时" : "已暂停")。").font(.callout); Button("查看专注") { store.destination = .focus } }
                    if let error = store.localError { Text(error).foregroundStyle(.red) }
                    if let error = store.sync?.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    Text("导出与备份").font(.title3.weight(.semibold))
                    if queueCount > 0 || store.focus?.snapshot != nil { Text("有未同步记录，导出仅含已确认数据").font(.callout).foregroundStyle(AtlasTheme.muted) }
                    HStack { Button("导出 JSON…", systemImage: "square.and.arrow.up") { export() }.disabled(working || store.account.isOffline); if working { ProgressView().controlSize(.small) }; if let exportPath { Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([exportPath]) } } }
                    if let exportPath { Text("已导出：\(exportPath.path)").font(.caption).textSelection(.enabled).foregroundStyle(AtlasTheme.muted) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    Text("专注通知").font(.title3.weight(.semibold))
                    Text(store.notifications.status).font(.callout).foregroundStyle(AtlasTheme.muted)
                    if store.notifications.enabled { Button("关闭专注通知") { store.notifications.disable() } }
                    else { Button("开启专注通知") { Task { await store.notifications.enable() } } }
                }
                Divider()
                Text("Skill Atlas \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")").font(.caption).foregroundStyle(AtlasTheme.muted)
            }.padding(28).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.background(AtlasTheme.ground)
            .confirmationDialog("退出当前账号？", isPresented: $signOut, titleVisibility: .visible) { Button("保存专注并退出") { Task { await store.account.signOut() } } } message: { Text("本机待上传记录会保留在当前账号下，其他账号不会上传或看到它们。") }
    }
    private func export() {
        working = true; error = nil; notice = nil
        Task {
            do {
                guard let owner = store.account.user?.id else { throw FocusEngineError.invalidIdentity }
                let document: ExportDocument = try await store.account.request("/v1/export")
                try document.validate(accountId: owner)
                let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.canCreateDirectories = true
                panel.title = "保存 Skill Atlas 备份"; panel.nameFieldStringValue = "SkillAtlas-\(Date.now.ISO8601Format().prefix(10)).json"
                let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning: $0) } }
                guard store.account.user?.id == owner else { throw CancellationError() }
                if response == .OK, let url = panel.url { try document.saveVerified(to: url); exportPath = url; notice = "导出完成，共 \(document.counts.values.reduce(0, +)) 条记录。" }
                else { notice = "已取消导出。" }
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}
