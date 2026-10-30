import SwiftUI

private struct GraphEditorSelection: Identifiable {
    enum Content { case tree(SkillTreeRecord?), skill(SkillRecord?, String, String?), link(String, SkillLinkRecord?) }
    let id = UUID()
    let content: Content
}

struct SkillGraphPage: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTree = ""
    @State private var selectedSkill: String?
    @State private var focusedSkill: String?
    @State private var viewports: [String: GraphViewport] = [:]
    @State private var includeArchived = false
    @State private var search = ""
    @State private var editor: GraphEditorSelection?
    @State private var deletion: SkillRecord?
    @State private var error: String?
    private var trees: [SkillTreeRecord] { store.library.trees.filter { includeArchived || $0.archivedAt == nil }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) } }
    private var current: SkillTreeRecord? { trees.first { $0.id == selectedTree } ?? trees.first }
    private var skills: [SkillRecord] { store.library.skills.filter { $0.treeId == current?.id && (includeArchived || $0.archivedAt == nil) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                PageHeading("技能星图")
                Spacer()
                Button { Task { await store.library.refresh(); await store.sync?.synchronize(force: true) } } label: { Image(systemName: "arrow.clockwise") }.help("刷新星图")
                if let current {
                    Button("新建技能", systemImage: "plus") { editor = .init(content: .skill(nil, current.id, nil)) }
                        .disabled(current.archivedAt != nil || store.account.isOffline)
                        .accessibilityIdentifier("skill-create")
                }
                Menu {
                    Button("新建技能树") { editor = .init(content: .tree(nil)) }
                    if let current { Button("编辑当前技能树") { editor = .init(content: .tree(current)) } }
                    Toggle("显示已归档", isOn: $includeArchived)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 28, height: 28)
                    .help("更多技能树操作").accessibilityLabel("更多技能树操作")
            }.controlSize(.large).padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 20)
            if let message = store.library.errorMessage { InlineFailure(message: message) { Task { await store.library.refresh() } }.padding(.horizontal, 28).padding(.bottom, 12) }
            if trees.isEmpty {
                EmptyWorkspace(symbol: "point.3.connected.trianglepath.dotted", title: "暂无技能树") {
                    Button("创建第一棵技能树") { editor = .init(content: .tree(nil)) }.disabled(store.account.isOffline)
                }
            } else if let current {
                HStack(spacing: 12) {
                    Picker("技能树", selection: Binding(get: { current.id }, set: { selectedTree = $0; selectedSkill = nil; focusedSkill = nil })) {
                        ForEach(trees) { Text($0.name + ($0.archivedAt == nil ? "" : " · 已归档")).tag($0.id) }
                    }.labelsHidden().pickerStyle(.menu)
                        .frame(maxWidth: 200, alignment: .leading).fixedSize(horizontal: true, vertical: false)
                        .help(current.name).accessibilityIdentifier("skill-tree-picker")
                    TextField("搜索技能", text: $search).textFieldStyle(.roundedBorder).frame(minWidth: 160, maxWidth: 280)
                        .accessibilityLabel("搜索技能").accessibilityIdentifier("skill-search")
                    Spacer(minLength: 0)
                }.controlSize(.regular).padding(.horizontal, 28).padding(.bottom, 16)
                GeometryReader { geometry in
                    ZStack(alignment: .trailing) {
                        if skills.isEmpty {
                            EmptyWorkspace(symbol: "star", title: "暂无技能") {
                                Button("新建技能") { editor = .init(content: .skill(nil, current.id, nil)) }.disabled(current.archivedAt != nil || store.account.isOffline)
                            }
                        } else {
                            SkillGraphCanvas(skills: skills, links: store.library.links, progress: store.sync?.progress ?? [], selected: selectedSkill, focusRequest: focusedSkill,
                                             viewport: Binding(get: { viewports[current.id] ?? .init() }, set: { viewports[current.id] = $0 }), select: { id in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { selectedSkill = id } })
                                .id(current.id)
                        }
                        if !search.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                let matches = store.library.skills.filter { (includeArchived || $0.archivedAt == nil) && $0.name.localizedCaseInsensitiveContains(search) }
                                if matches.isEmpty { Text("没有匹配的技能").foregroundStyle(AtlasTheme.muted).padding(14) }
                                ForEach(matches.prefix(8)) { skill in
                                    Button { locate(skill.id); search = "" } label: {
                                        HStack { Image(systemName: SkillIcon.find(skill.iconKey).symbol); Text(skill.name); Spacer(); Text(store.library.trees.first { $0.id == skill.treeId }?.name ?? "").foregroundStyle(AtlasTheme.muted) }.font(.callout).padding(12).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }.frame(width: min(400, geometry.size.width - 32)).background(AtlasTheme.surface).overlay(Rectangle().stroke(AtlasTheme.raised))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 28).zIndex(2)
                        }
                        if let id = selectedSkill, let skill = store.library.skills.first(where: { $0.id == id && $0.treeId == current.id }) {
                            SkillDrawer(skill: skill, close: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { selectedSkill = nil } }, locate: locate,
                                        edit: { editor = .init(content: .skill(skill, skill.treeId, skill.parentSkillId)) }, addChild: { editor = .init(content: .skill(nil, skill.treeId, skill.id)) },
                                        addLink: { editor = .init(content: .link(skill.id, nil)) }, editLink: { editor = .init(content: .link(skill.id, $0)) }, delete: { deletion = skill })
                                .id(skill.id).frame(width: min(384, max(300, geometry.size.width * 0.55)), height: geometry.size.height)
                                .background(AtlasTheme.surface).overlay(alignment: .leading) { Rectangle().fill(AtlasTheme.raised).frame(width: 1) }.transition(.move(edge: .trailing)).zIndex(1)
                        }
                    }
                }
            }
        }.background(AtlasTheme.ground)
            .onAppear { if let id = store.requestedSkillId { locate(id) } }
            .onChange(of: store.requestedSkillId) { _, id in if let id { locate(id) } }
            .sheet(item: $editor) { selection in
                switch selection.content {
                case .tree(let tree): TreeEditor(tree: tree) { id in
                    if selectedTree != id { selectedSkill = nil; focusedSkill = nil }
                    selectedTree = id
                }
                case .skill(let skill, let tree, let parent): SkillEditor(skill: skill, treeId: tree, parentId: parent)
                case .link(let skill, let existing): SkillLinkEditor(skillId: skill, existing: existing)
                }
            }
            .alert("删除这项技能？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                Button("返回", role: .cancel) { deletion = nil }
                Button("删除", role: .destructive) { if let value = deletion { Task { do { try await store.library.delete(value); selectedSkill = nil } catch { self.error = error.localizedDescription } } }; deletion = nil }
            } message: { Text("有子技能、关系、任务或历史记录的技能需要归档。操作日志会保留。") }
            .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
    private func locate(_ id: String) {
        guard let skill = store.library.skills.first(where: { $0.id == id }) else { return }
        if skill.archivedAt != nil || store.library.trees.first(where: { $0.id == skill.treeId })?.archivedAt != nil { includeArchived = true }
        selectedTree = skill.treeId; selectedSkill = id; focusedSkill = id
    }
}
