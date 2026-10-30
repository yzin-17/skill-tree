import SwiftUI

struct FocusWorkspaceView: View {
    @Environment(ApplicationStore.self) private var store
    @State private var mode = FocusMode.countUp
    @State private var skillId = ""
    @State private var taskId = ""
    @State private var minutes = "25"
    @State private var seconds = "0"
    @State private var restMinutes = "5"
    @State private var rounds = 4
    @State private var error: String?
    @State private var showManual = false
    private var active: FocusSnapshot? { store.focus?.snapshot }
    private var selectedSkill: SkillRecord? { store.library.skills.first { $0.id == (active?.skillId ?? skillId) } }
    private var progress: SkillProgress? { store.sync?.progress.first { $0.skillId == (active?.skillId ?? skillId) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    PageHeading("专注")
                    Spacer(); Button("手动补录", systemImage: "square.and.pencil") { showManual = true }.disabled(store.focus == nil)
                }
                if let localError = store.localError { Label(localError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if let focusError = store.focus?.persistenceError { Label(focusError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if let error { Text(error).font(.callout).foregroundStyle(.orange) }
                if let notice = store.focus?.notice { Label(notice, systemImage: "pause.circle").font(.callout).foregroundStyle(AtlasTheme.muted) }
                if let active { activeSession(active) }
                else { setup }
                if let progress {
                    HStack(spacing: 24) {
                        Text("\(selectedSkill?.name ?? "技能")  Lv.\(progress.level)").font(.headline)
                        ProgressView(value: Double(progress.xpCurrent), total: Double(progress.xpRequired)).tint(AtlasTheme.growth).frame(maxWidth: 220)
                        Text("\(progress.xpCurrent)/\(progress.xpRequired) XP").font(.callout).monospacedDigit().foregroundStyle(AtlasTheme.muted)
                    }
                    if !progress.unlocked {
                        Label("前置条件未达成", systemImage: "lock.open").font(.callout).foregroundStyle(AtlasTheme.muted)
                    }
                }
                FocusSyncPanel()
                HStack {
                    VStack(alignment: .leading, spacing: 6) { Text("到点提醒").font(.callout.weight(.medium)); Text(store.notifications.status).font(.caption).foregroundStyle(AtlasTheme.muted) }
                    Spacer()
                    if store.notifications.enabled { Button("关闭提醒") { store.notifications.disable() } }
                    else { Button("开启提醒") { Task { await store.notifications.enable() } } }
                }
                Divider(); FocusHistoryView()
            }.padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }.background(AtlasTheme.ground)
            .onAppear(perform: applyRequest)
            .onChange(of: store.requestedTaskId) { _, _ in applyRequest() }
            .onChange(of: store.requestedSkillId) { _, _ in applyRequest() }
            .sheet(isPresented: $showManual) { ManualFocusEditor() }
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    fieldLabel("计时模式")
                    Picker("计时模式", selection: $mode) { ForEach(FocusMode.allCases) { Text($0.name).tag($0) } }.labelsHidden().pickerStyle(.segmented).fixedSize().frame(maxWidth: 340, alignment: .leading)
                }
                GridRow {
                    fieldLabel("主技能")
                    Picker("主技能", selection: $skillId) { Text("请选择一项技能").tag(""); ForEach(store.library.activeSkills) { Text($0.name).tag($0.id) } }.labelsHidden().frame(maxWidth: 340, alignment: .leading)
                }
                GridRow {
                    fieldLabel("关联任务")
                    Picker("关联任务", selection: $taskId) {
                        Text("自由专注").tag(""); ForEach(store.tasks.sorted.filter { $0.status.canConclude }) { Text($0.title).tag($0.id) }
                    }.labelsHidden().frame(maxWidth: 340, alignment: .leading)
                }
                if mode != .countUp {
                    GridRow {
                        fieldLabel(mode == .pomodoro ? "每轮专注" : "目标时长")
                        HStack(spacing: 8) {
                            TextField("分钟", text: $minutes).textFieldStyle(.roundedBorder).frame(width: 55); Text("分")
                            TextField("秒", text: $seconds).textFieldStyle(.roundedBorder).frame(width: 48); Text("秒")
                        }
                    }
                }
                if mode == .pomodoro {
                    GridRow {
                        fieldLabel("休息与轮次")
                        HStack(spacing: 8) {
                            TextField("休息分钟", text: $restMinutes).textFieldStyle(.roundedBorder).frame(width: 55); Text("分")
                            Stepper("\(rounds) 轮专注", value: $rounds, in: 1...24).fixedSize().padding(.leading, 8)
                        }
                    }
                }
            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 18) {
                Button("开始专注", systemImage: "play.fill", action: start).buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(skillId.isEmpty || store.focus == nil)
                if store.account.isOffline { Label("当前离线", systemImage: "wifi.slash").font(.caption).foregroundStyle(AtlasTheme.muted) }
            }
            if store.library.activeSkills.isEmpty { Button("先创建一项技能") { store.destination = .skills } }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func fieldLabel(_ text: String) -> some View { Text(text).font(.callout).foregroundStyle(AtlasTheme.muted).frame(width: 80, alignment: .trailing) }
    private func activeSession(_ current: FocusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    Label(selectedSkill?.name ?? "当前技能", systemImage: SkillIcon.find(selectedSkill?.iconKey ?? "star").symbol).font(.title3.weight(.medium))
                    Text(current.configuration.mode.name + (current.configuration.mode == .pomodoro ? " · 第 \(current.round)/\(current.configuration.rounds) 轮" : ""))
                        .font(.callout).foregroundStyle(AtlasTheme.muted)
                }
                Spacer()
                Label(current.status == .paused ? "已暂停" : current.phase == .rest ? "休息中" : "专注中", systemImage: current.status == .paused ? "pause.circle" : current.phase == .rest ? "cup.and.saucer" : "timer")
                    .font(.callout).foregroundStyle(AtlasTheme.muted)
            }
            Text(AtlasFormat.clock(current.remainingSeconds ?? current.effectiveSeconds))
                .font(.system(size: 76, weight: .light, design: .rounded)).monospacedDigit().contentTransition(.identity)
            HStack(spacing: 24) {
                Text("有效专注  \(AtlasFormat.clock(current.effectiveSeconds))").monospacedDigit()
                Text(AtlasFormat.xpForecast(current.effectiveSeconds)).font(.caption).foregroundStyle(AtlasTheme.muted)
                if let task = store.tasks.items.first(where: { $0.id == current.taskId }) { Text(task.title).lineLimit(1) }
            }.font(.callout).foregroundStyle(AtlasTheme.muted)
            TextField("结束备注（可选）", text: Binding(get: { store.focus?.snapshot?.note ?? "" }, set: { value in perform { try store.focus?.updateNote(value) } })).textFieldStyle(.roundedBorder)
            HStack(spacing: 14) {
                Button(current.status == .running ? "暂停" : "继续", systemImage: current.status == .running ? "pause.fill" : "play.fill") {
                    perform { if current.status == .running { try store.focus?.pause() } else { try store.focus?.resume() } }
                }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("结束并保存", systemImage: "stop.fill") { perform { try store.focus?.finish() } }.controlSize(.large)
            }
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func applyRequest() {
        if let id = store.requestedSkillId { skillId = store.library.activeSkills.contains { $0.id == id } ? id : "" }
        if let id = store.requestedTaskId { taskId = store.tasks.items.contains { $0.id == id && $0.status.canConclude } ? id : "" }
    }
    private func start() {
        perform {
            guard store.library.activeSkills.contains(where: { $0.id == skillId }) else { throw FocusEngineError.invalidIdentity }
            var config = FocusConfiguration(mode: mode)
            if mode != .countUp {
                guard let m = Int(minutes), let s = Int(seconds), (0...1440).contains(m), (0...59).contains(s) else { throw FocusEngineError.invalidConfiguration }
                config.targetSeconds = m * 60 + s
            }
            if mode == .pomodoro {
                guard let rest = Int(restMinutes), (0...1440).contains(rest) else { throw FocusEngineError.invalidConfiguration }
                config.restSeconds = rest * 60; config.rounds = rounds
            }
            try config.validate(); try store.focus?.start(skillId: skillId, taskId: taskId.isEmpty ? nil : taskId, configuration: config)
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); error = nil } catch { self.error = error.localizedDescription } }
}

struct FocusSyncPanel: View {
    @Environment(ApplicationStore.self) private var store
    private var rows: [LocalFocusRecord] {
        guard let sync = store.sync else { return [] }
        return sync.records.filter { $0.state != .confirmed || $0.id == store.focus?.lastFinished?.id }.sorted { $0.submission.endedAt > $1.submission.endedAt }
    }
    var body: some View {
        if let sync = store.sync {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(sync.isSyncing ? "正在同步" : sync.pendingCount + sync.blockedCount + sync.activityCount == 0 ? "记录已同步" : "记录已保存在本机", systemImage: sync.isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.shield")
                    Spacer()
                    if sync.pendingCount + sync.blockedCount + sync.activityCount > 0 {
                        Button("重试同步") { Task { await sync.synchronize(force: true) } }.disabled(sync.isSyncing)
                    }
                }.font(.callout)
                if let message = sync.errorMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                ForEach(rows) { record in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AtlasFormat.duration(record.submission.effectiveSeconds)).font(.system(size: 16, weight: .medium)).monospacedDigit()
                            Text(store.library.skills.first { $0.id == record.submission.skillId }?.name ?? "历史技能").font(.caption).foregroundStyle(AtlasTheme.muted)
                            if let failure = record.failure { Text(failure).font(.caption).foregroundStyle(.orange) }
                        }
                        Spacer()
                        switch record.state {
                        case .confirmed: Text("已确认 +\(record.confirmation?.awardedXp ?? 0) XP").foregroundStyle(AtlasTheme.growth)
                        case .pending: VStack(alignment: .trailing, spacing: 6) { Text(AtlasFormat.xpForecast(record.submission.effectiveSeconds)); Text("经验待服务端确认").font(.caption) }.foregroundStyle(AtlasTheme.muted)
                        case .blocked: Label("同步冲突", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        }
                    }.font(.callout)
                }
                if sync.blockedActivityCount > 0 {
                    ForEach(sync.activities.filter(\.blocked)) { event in Text(event.failure ?? "计时事件同步发生冲突，原记录已保留。").font(.caption).foregroundStyle(.orange) }
                }
            }.padding(.vertical, 8)
        }
    }
}
