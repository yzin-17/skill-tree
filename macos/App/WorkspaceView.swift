import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case overview = "工作台", skills = "技能星图", tasks = "任务", focus = "专注", achievements = "成就殿堂", activity = "成长日志", settings = "设置"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .skills: "point.3.connected.trianglepath.dotted"
        case .tasks: "checklist"
        case .focus: "timer"
        case .achievements: "medal"
        case .activity: "chart.xyaxis.line"
        case .settings: "gearshape"
        }
    }
}

enum AtlasTheme {
    static let ground = Color(white: 0.035)
    static let surface = Color(white: 0.075)
    static let raised = Color(white: 0.16)
    static let muted = Color(white: 0.70)
    static let growth = Color(red: 0.40, green: 0.67, blue: 0.96)
}

struct WorkspaceView: View {
    @Environment(ApplicationStore.self) private var store
    private var destination: Destination? { store.destination }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.title2)
                    Text("Skill Atlas").font(.system(size: 17, weight: .semibold))
                }.padding(.horizontal, 20).padding(.top, 24)
                List(Destination.allCases, selection: Binding(get: { Optional(store.destination) }, set: { if let value = $0 { store.destination = value } })) { item in
                    Label(item.rawValue, systemImage: item.symbol).tag(item)
                        .padding(.vertical, 6)
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                Label(store.health == nil ? "服务未连接" : "后端已连接", systemImage: store.health == nil ? "network.slash" : "checkmark.shield")
                    .font(.caption).foregroundStyle(AtlasTheme.muted).padding(20)
            }.frame(minWidth: 190, idealWidth: 212, maxWidth: 240).background(AtlasTheme.ground)
            Group {
            if destination == .skills { SkillGraphPage() }
            else if destination == .tasks { TaskPage() }
            else if destination == .focus { FocusWorkspaceView() }
            else if destination == .achievements { AchievementPage() }
            else if destination == .activity { ActivityWorkspace() }
            else if destination == .settings { SettingsPage() }
            else { DashboardView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.task { await store.checkConnection() }
            .onChange(of: store.sync?.confirmedFocusRevision) { _, _ in Task { await store.achievements.refresh() } }
    }
}

struct ConnectionPanel: View {
    @Environment(ApplicationStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 16) {
            Image(systemName: store.health == nil ? "network" : "checkmark.shield")
                .font(.system(size: 22, weight: .light))
            VStack(alignment: .leading, spacing: 6) {
                Text(store.isChecking ? "正在连接后端" : store.health == nil ? "连接暂不可用" : "后端服务已就绪")
                    .font(.system(size: 14, weight: .medium))
                if let error = store.connectionError {
                    Text(error).font(.system(size: 12)).foregroundStyle(AtlasTheme.muted).textSelection(.enabled)
                }
            }
            Spacer(minLength: 16)
            Button { Task { await store.checkConnection() } } label: {
                if store.isChecking { ProgressView().controlSize(.small) } else { Label("检查连接", systemImage: "arrow.clockwise") }
            }.disabled(store.isChecking).controlSize(.large)
        }
        HStack(spacing: 16) {
            Text(store.backendAddress?.text ?? "未配置地址").font(.callout).foregroundStyle(AtlasTheme.muted)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                .accessibilityIdentifier("backend-current-address")
            Spacer(minLength: 16)
            Button("编辑地址") { store.isBackendEditorPresented = true }.disabled(store.account.isBusy)
                .controlSize(.large).accessibilityIdentifier("backend-address-edit")
        }
        }.padding(22).background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain).accessibilityIdentifier("connection-panel")
    }
}
