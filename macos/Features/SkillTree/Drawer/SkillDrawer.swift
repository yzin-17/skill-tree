import SwiftUI

struct SkillDrawer: View {
    @Environment(ApplicationStore.self) private var store
    let skill: SkillRecord
    let close: () -> Void
    let locate: (String) -> Void
    let edit: () -> Void
    let addChild: () -> Void
    let addLink: () -> Void
    let editLink: (SkillLinkRecord) -> Void
    let delete: () -> Void
    @State private var removing: SkillLinkRecord?
    @State private var error: String?
    private var progress: SkillProgress? { store.sync?.progress.first { $0.skillId == skill.id } }
    private var links: [SkillLinkRecord] { store.library.links.filter { $0.fromSkillId == skill.id || $0.toSkillId == skill.id } }
    private var available: Bool { store.library.activeSkills.contains { $0.id == skill.id } }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("技能详情").font(.caption).foregroundStyle(AtlasTheme.muted); Spacer(); Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭详情，保留星图视口") }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: SkillIcon.find(skill.iconKey).symbol).font(.system(size: 30, weight: .light)).frame(width: 40)
                        VStack(alignment: .leading, spacing: 8) { Text(skill.name).font(.title2.weight(.semibold)); Text("Lv.\(progress?.level ?? 1)").font(.callout).foregroundStyle(AtlasTheme.growth) }
                        Spacer()
                    }
                    if !skill.description.isEmpty { Text(skill.description).font(.callout).foregroundStyle(AtlasTheme.muted).textSelection(.enabled) }
                    if let progress {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: Double(progress.xpCurrent), total: Double(progress.xpRequired)).tint(AtlasTheme.growth)
                            Text("\(progress.xpCurrent) / \(progress.xpRequired) XP · 累计 \(progress.totalXp) XP").font(.caption).foregroundStyle(AtlasTheme.muted)
                            Text("时间 \(progress.timeXp) XP · 任务奖励 \(progress.taskBonusXp) XP").font(.caption).foregroundStyle(AtlasTheme.muted)
                            Text("累计投入 \(AtlasFormat.duration(progress.totalFocusSeconds))").font(.callout)
                        }
                        if !progress.unlocked {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("前置条件未满足", systemImage: "lock").font(.callout.weight(.medium))
                                ForEach(progress.missingPrerequisites) { missing in
                                    Button { locate(missing.skillId) } label: { Text("\(missing.name)：Lv.\(missing.currentLevel) / \(missing.requiredLevel)").font(.caption) }.buttonStyle(.link)
                                }
                            }
                        }
                    }
                    HStack { Button("开始专注", systemImage: "play.fill") { store.prepareFocus(skillId: skill.id) }.buttonStyle(.borderedProminent).disabled(!available); Button("编辑", action: edit).disabled(store.account.isOffline) }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("技能层级").font(.headline); Spacer(); Button("添加子技能", action: addChild).font(.caption).disabled(!available || store.account.isOffline) }
                        if let parent = skill.parentSkillId { skillButton(parent, prefix: "父技能") }
                        let children = store.library.skills.filter { $0.parentSkillId == skill.id }
                        if children.isEmpty { Text("暂无子技能").font(.caption).foregroundStyle(AtlasTheme.muted) }
                        ForEach(children) { child in skillButton(child.id, prefix: "子技能") }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("前置与关联").font(.headline); Spacer(); Button("添加", action: addLink).disabled(store.account.isOffline || !available) }
                        if links.isEmpty { Text("暂无关系").font(.caption).foregroundStyle(AtlasTheme.muted) }
                        ForEach(links) { link in
                            let other = link.fromSkillId == skill.id ? link.toSkillId : link.fromSkillId
                            VStack(alignment: .leading, spacing: 7) {
                                skillButton(other, prefix: link.linkType == .reference ? "关联" : link.fromSkillId == skill.id ? "需要" : "解锁目标")
                                HStack {
                                    Text(link.requiredLevel.map { "前置达到 Lv.\($0)" } ?? "普通关联").font(.caption).foregroundStyle(AtlasTheme.muted)
                                    Spacer()
                                    if link.linkType == .prerequisite { Button("调整") { editLink(link) }.font(.caption) }
                                    Button { removing = link } label: { Image(systemName: "minus.circle") }.help("移除关系")
                                }.disabled(store.account.isOffline)
                            }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("关联任务").font(.headline)
                        let tasks = store.tasks.sorted.filter { $0.skills.contains { $0.skillId == skill.id } }
                        if tasks.isEmpty { Text("暂无关联任务").font(.caption).foregroundStyle(AtlasTheme.muted) }
                        ForEach(tasks) { item in Button { store.openTask(item.id) } label: { HStack { Text(item.title).lineLimit(2); Spacer(); Text(item.status.label).foregroundStyle(AtlasTheme.muted) }.font(.callout) }.buttonStyle(.plain) }
                    }
                    Divider(); FocusHistoryView(skillId: skill.id)
                    Divider()
                    Button("删除无引用技能", role: .destructive, action: delete).font(.caption).disabled(store.account.isOffline)
                }.padding(22)
            }
        }
        .confirmationDialog("移除这项关系？技能和历史记录会保留。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("移除关系", role: .destructive) { if let link = removing { Task { do { try await store.library.removeLink(link); await store.sync?.synchronize(force: true) } catch { self.error = error.localizedDescription } } }; removing = nil }
        }
        .alert("关系未更新", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
    private func skillButton(_ id: String, prefix: String) -> some View {
        let target = store.library.skills.first { $0.id == id }
        return Button { locate(id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(prefix) · \(target?.name ?? "历史技能")").font(.callout)
                if let target, target.treeId != skill.treeId { Text(store.library.trees.first { $0.id == target.treeId }?.name ?? "其他技能树").font(.caption).foregroundStyle(AtlasTheme.muted) }
            }
        }.buttonStyle(.link)
    }
}
