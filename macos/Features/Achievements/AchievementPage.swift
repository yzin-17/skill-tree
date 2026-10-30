import SwiftUI

private struct AchievementEditorSelection: Identifiable {
    enum Content { case career(CareerRecord?), title(TitleRecord?) }
    let id = UUID()
    let content: Content
}

struct AchievementPage: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editor: AchievementEditorSelection?
    @State private var selectedCareer: String?
    @State private var selectedTitle: String?
    @State private var titleFilter = "all"
    @State private var transition: CareerRecord?
    @State private var reveal: String?
    @State private var error: String?
    @AccessibilityFocusState private var detailFocused: Bool
    private var library: AchievementLibrary { store.achievements }
    private var canAct: Bool { !store.account.isOffline && !library.busy && library.pending == nil }
    private var visibleTitles: [TitleRecord] {
        (library.titles?.items ?? []).filter { titleFilter == "all" || (titleFilter == "unlocked" ? $0.unlockedAt != nil : $0.unlockedAt == nil) }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                page
                if selectedCareer != nil || selectedTitle != nil {
                    detailPanel
                        .frame(width: min(384, max(320, geometry.size.width * 0.62)), height: geometry.size.height)
                        .background(AtlasTheme.surface)
                        .overlay(alignment: .leading) { Rectangle().fill(AtlasTheme.raised).frame(width: 1) }
                        .accessibilityIdentifier("achievement-detail-panel")
                }
            }
        }.background(AtlasTheme.ground)
            .onExitCommand { closeDetails() }
    }
    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { PageHeading("成就殿堂"); Spacer(); Button { Task { await library.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("刷新成就") }
                if let message = error ?? library.errorMessage { InlineFailure(message: AchievementDisplay.message(message)) { Task { await library.refresh(); error = nil } } }
                if library.pending != nil {
                    HStack { Label("上次成就操作的结果尚未确认", systemImage: "arrow.triangle.2.circlepath"); Spacer(); Button("重新确认") { run { try await library.retryPending() } }.disabled(library.busy || store.account.isOffline) }.font(.callout).padding(18).background(AtlasTheme.surface)
                }
                profile
                if let reveal { Label("已进入阶段「\(reveal)」", systemImage: "sparkles").font(.title3).foregroundStyle(AtlasTheme.growth).transition(.opacity) }
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Text("成长路径").font(.title3.weight(.semibold)); Spacer(); Button("添加阶段", systemImage: "plus") { editor = .init(content: .career(nil)) }.disabled(!canAct) }
                    if let catalog = library.careers {
                        if catalog.items.isEmpty { Text("尚无成长阶段").foregroundStyle(AtlasTheme.muted).padding(.vertical, 20) }
                        else {
                            GrowthPathTree(catalog: catalog, selected: Binding(get: { selectedCareer }, set: { selectedCareer = $0; selectedTitle = nil }))
                        }
                        if !catalog.history.isEmpty {
                            DisclosureGroup("阶段历程 · \(catalog.history.count) 次") {
                                VStack(alignment: .leading, spacing: 18) {
                                    ForEach(catalog.history) { entry in
                                        DisclosureGroup {
                                            ConditionEvidenceView(evaluation: entry.evidenceSnapshot).padding(.top, 12)
                                        } label: {
                                            Text("\(entry.confirmedAt.formatted(date: .abbreviated, time: .shortened)) · \(catalog.items.first { $0.id == entry.toCareerId }?.name ?? "成长阶段")").font(.callout)
                                        }
                                    }
                                }.padding(.top, 16)
                            }.foregroundStyle(AtlasTheme.muted)
                        }
                    } else { ProgressView("正在读取成长路径") }
                }
                Divider()
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Text("称号收藏").font(.title3.weight(.semibold)); Spacer(); Picker("显示", selection: $titleFilter) { Text("全部").tag("all"); Text("已解锁").tag("unlocked"); Text("未解锁").tag("locked") }.labelsHidden().frame(width: 130); Button("新建称号", systemImage: "plus") { editor = .init(content: .title(nil)) }.disabled(!canAct) }
                    if let catalog = library.titles {
                        let filtered = visibleTitles
                        if filtered.isEmpty { Text(catalog.items.isEmpty ? "尚无称号" : "这个筛选下还没有称号。").foregroundStyle(AtlasTheme.muted).padding(.vertical, 20) }
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(filtered) { title in
                                Button { selectedTitle = title.id; selectedCareer = nil } label: {
                                    HStack(alignment: .top, spacing: 14) {
                                        Image(systemName: SkillIcon.find(title.iconKey).symbol).font(.system(size: 22, weight: .light)).foregroundStyle(title.unlockedAt != nil ? AtlasTheme.growth : AtlasTheme.muted).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(title.name).font(.headline)
                                                Spacer()
                                                Text(catalog.equippedTitleId == title.id ? "正在佩戴" : title.unlockedAt == nil ? "未解锁" : title.evaluation.eligible ? "已解锁 · 可佩戴" : "已解锁 · 当前资格未满足").font(.caption).foregroundStyle(AtlasTheme.muted)
                                            }
                                            ConditionProgressSummary(evaluation: title.evaluation)
                                        }
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(AtlasTheme.muted)
                                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(selectedTitle == title.id ? AtlasTheme.raised : AtlasTheme.surface)
                                }.buttonStyle(.plain).accessibilityIdentifier("title-row-" + title.id)
                            }
                        }
                    } else { ProgressView("正在读取称号") }
                }
            }.padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }.background(AtlasTheme.ground).task { await library.refresh() }
            .onChange(of: visibleTitles.map(\.id)) { _, ids in if let selectedTitle, !ids.contains(selectedTitle) { self.selectedTitle = nil } }
            .onChange(of: library.careers?.items.map(\.id)) { _, ids in if let selectedCareer, !(ids ?? []).contains(selectedCareer) { self.selectedCareer = nil } }
            .onChange(of: selectedCareer ?? selectedTitle) { _, value in detailFocused = value != nil }
            .sheet(item: $editor) { switch $0.content { case .career(let item): CareerEditor(career: item); case .title(let item): TitleEditor(title: item) } }
            .sheet(item: $transition) { career in
                VStack(alignment: .leading, spacing: 22) {
                    Text("进入阶段「\(career.name)」").font(.title2.weight(.semibold))
                    Text("将切换当前阶段并保存达成记录。").font(.callout).foregroundStyle(AtlasTheme.muted)
                    ScrollView { ConditionEvidenceView(evaluation: career.evaluation) }.frame(maxHeight: 320)
                    HStack { Spacer(); Button("返回") { transition = nil }; Button("确认进入") { transition = nil; run { try await library.transition(career); withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { reveal = career.name } } }.buttonStyle(.borderedProminent) }
                }.padding(28).frame(width: 470)
            }
    }
    private func closeDetails() { selectedCareer = nil; selectedTitle = nil }
    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedCareer != nil ? "阶段详情" : "称号详情").font(.headline).accessibilityFocused($detailFocused)
                Spacer()
                Button(action: closeDetails) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).help("关闭详情").accessibilityLabel("关闭成就详情")
            }.padding(20)
            Divider()
            ScrollView {
                if let catalog = library.careers, let stage = catalog.items.first(where: { $0.id == selectedCareer }) {
                    careerDetail(stage, catalog: catalog)
                } else if let catalog = library.titles, let title = visibleTitles.first(where: { $0.id == selectedTitle }) {
                    titleDetail(title, catalog: catalog)
                }
            }
        }
    }
    private var profile: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: SkillIcon.find(library.currentCareer?.badgeKey ?? "compass").symbol).font(.system(size: 28, weight: .light)).frame(width: 36)
            VStack(alignment: .leading, spacing: 10) {
                Text(library.currentCareer?.name ?? "尚未选择阶段").font(.system(size: 20, weight: .semibold))
                Text(library.equippedTitle.map { "称号 · \($0.name)" } ?? "尚未佩戴称号").font(.callout).foregroundStyle(AtlasTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Text("累计专注 \(AtlasFormat.duration((store.sync?.progress ?? []).reduce(Int64(0)) { $0 + $1.totalFocusSeconds }))").font(.callout)
                Text("成功尝试 \(store.tasks.items.reduce(Int64(0)) { $0 + $1.attemptSummary.successes }) 次").font(.caption).foregroundStyle(AtlasTheme.muted)
            }
        }.padding(16).background(AtlasTheme.surface)
    }
    private func careerDetail(_ career: CareerRecord, catalog: CareerCatalog) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(career.name).font(.headline); Spacer(); Button("编辑条件") { editor = .init(content: .career(career)) }.disabled(!canAct) }
            if !career.description.isEmpty { Text(career.description).font(.callout).foregroundStyle(AtlasTheme.muted) }
            ConditionEvidenceView(evaluation: career.evaluation)
            if !career.parentReached { Text("前一阶段未达成：\(catalog.items.first { $0.id == career.parentCareerId }?.name ?? "前一阶段")").font(.callout).foregroundStyle(AtlasTheme.muted) }
            Button(catalog.currentCareerId == career.id ? "当前阶段" : "确认进入") { transition = career }.buttonStyle(.borderedProminent).disabled(!canAct || !career.evaluation.eligible || !career.parentReached || catalog.currentCareerId == career.id)
        }.padding(20)
    }
    private func titleDetail(_ title: TitleRecord, catalog: TitleCatalog) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(title.name).font(.headline); Spacer(); Button("编辑条件") { editor = .init(content: .title(title)) }.disabled(!canAct) }
            if !title.description.isEmpty { Text(title.description).font(.callout).foregroundStyle(AtlasTheme.muted) }
            ConditionEvidenceView(evaluation: title.evaluation)
            if let date = title.unlockedAt, let evidence = title.unlockedEvidence { DisclosureGroup("首次解锁 · \(date.formatted(date: .abbreviated, time: .shortened))") { ConditionEvidenceView(evaluation: evidence).padding(.top, 14) }.font(.callout) }
            HStack {
                if catalog.equippedTitleId == title.id { Button("取消佩戴") { run { try await library.equip(nil) } }.disabled(!canAct) }
                else { Button("佩戴称号") { run { try await library.equip(title) } }.buttonStyle(.borderedProminent).disabled(!canAct || !title.evaluation.eligible || title.unlockedAt == nil) }
            }
        }.padding(20)
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) { Task { do { try await operation(); error = nil } catch { self.error = error.localizedDescription } } }
}
