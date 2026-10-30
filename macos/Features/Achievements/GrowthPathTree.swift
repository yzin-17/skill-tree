import SwiftUI

struct GrowthPathTree: View {
    let catalog: CareerCatalog
    @Binding var selected: String?
    private var layout: GrowthPathLayout {
        .init(nodes: catalog.items.map { .init(id: $0.id, parentID: $0.parentCareerId, name: $0.name, order: $0.sortOrder) })
    }
    var body: some View {
        let tree = layout
        let byID = Dictionary(catalog.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Path { path in
                        for edge in tree.edges {
                            if let parent = tree.positions[edge.parent], let child = tree.positions[edge.child] {
                                let start = CGPoint(x: parent.x + GrowthPathLayout.nodeWidth / 2, y: parent.y)
                                let end = CGPoint(x: child.x - GrowthPathLayout.nodeWidth / 2, y: child.y)
                                let middle = (start.x + end.x) / 2
                                path.move(to: start)
                                path.addCurve(to: end, control1: CGPoint(x: middle, y: start.y), control2: CGPoint(x: middle, y: end.y))
                            }
                        }
                    }.stroke(AtlasTheme.muted.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).accessibilityHidden(true)
                    ForEach(tree.orderedIDs, id: \.self) { id in
                        if let stage = byID[id], let position = tree.positions[id] {
                            GrowthStageNode(stage: stage, catalog: catalog, selected: selected == id) { selected = id }
                                .frame(width: GrowthPathLayout.nodeWidth, height: GrowthPathLayout.nodeHeight)
                                .position(x: position.x, y: position.y)
                        }
                    }
                }.frame(width: max(tree.width, geometry.size.width), height: tree.height, alignment: .topLeading)
            }.accessibilityIdentifier("growth-path-tree")
        }.frame(height: min(360, max(176, tree.height)))
    }
}

enum GrowthStagePresentation {
    static func status(_ stage: CareerRecord, catalog: CareerCatalog) -> String {
        if catalog.currentCareerId == stage.id { return "当前阶段" }
        if catalog.history.contains(where: { $0.toCareerId == stage.id }) { return "已达成" }
        return stage.evaluation.eligible && stage.parentReached ? "可进入" : "待达成"
    }
}

private struct GrowthStageNode: View {
    @Environment(ApplicationStore.self) private var store
    let stage: CareerRecord
    let catalog: CareerCatalog
    let selected: Bool
    let select: () -> Void
    private var met: Int { stage.evaluation.evidence.filter(\.met).count }
    private var status: String { GrowthStagePresentation.status(stage, catalog: catalog) }
    private var gap: String? {
        guard let item = stage.evaluation.evidence.first(where: { !$0.met }) else { return nil }
        let name = item.condition.skillId.flatMap { id in store.library.skills.first { $0.id == id }?.name }
            ?? item.condition.taskId.flatMap { id in store.tasks.items.first { $0.id == id }?.title } ?? "任务成功"
        return "\(name)  \(item.current) / \(item.required) \(item.unit)"
    }
    private var accessibilityName: String {
        let parent = stage.parentCareerId.flatMap { id in catalog.items.first { $0.id == id }?.name }
        return "\(stage.name)，\(status)，条件达成 \(met) / \(stage.evaluation.evidence.count)" + (gap.map { "，\($0)" } ?? "") + (parent.map { "，前一阶段 \($0)" } ?? "")
    }
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: SkillIcon.find(stage.badgeKey).symbol).font(.system(size: 18, weight: .light)).foregroundStyle(AtlasTheme.muted)
                    Text(stage.name).font(.callout.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(status).font(.caption).foregroundStyle(catalog.currentCareerId == stage.id ? AtlasTheme.growth : AtlasTheme.muted)
                HStack(spacing: 10) {
                    ProgressView(value: Double(met), total: Double(max(1, stage.evaluation.evidence.count))).tint(AtlasTheme.growth)
                    Text("\(met) / \(stage.evaluation.evidence.count)").font(.caption).monospacedDigit().foregroundStyle(AtlasTheme.muted)
                }
                if let gap { Text(gap).font(.caption).foregroundStyle(AtlasTheme.muted).lineLimit(1) }
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(selected ? AtlasTheme.raised : AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? AtlasTheme.growth : AtlasTheme.raised, lineWidth: selected ? 1.5 : 1) }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
            .help(stage.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { select() }
            .accessibilityHint("打开阶段详情")
            .accessibilityIdentifier("growth-stage-" + stage.id)
    }
}
