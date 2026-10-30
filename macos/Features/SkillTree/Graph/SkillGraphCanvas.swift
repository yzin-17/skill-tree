import SwiftUI

struct GraphViewport {
    var scale: CGFloat = 1
    var offset = CGSize.zero
    var initialized = false
}

struct SkillGraphCanvas: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skills: [SkillRecord]
    let links: [SkillLinkRecord]
    let progress: [SkillProgress]
    let selected: String?
    let focusRequest: String?
    @Binding var viewport: GraphViewport
    let select: (String) -> Void
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnify: CGFloat = 1
    private var layout: SkillGraphLayout { .init(skills: skills) }
    var body: some View {
        GeometryReader { geometry in
            let model = layout
            let scale = min(2, max(0.3, viewport.scale * magnify))
            let offset = CGSize(width: viewport.offset.width + drag.width, height: viewport.offset.height + drag.height)
            ZStack {
                AtlasTheme.ground
                Canvas { context, size in
                    func point(_ id: String) -> CGPoint? { model.positions[id].map { graphScreen($0, size: size, scale: scale, model: model, offset: offset) } }
                    func edge(_ a: String, _ b: String, color: Color, dash: [CGFloat], arrow: Bool) {
                        guard let start = point(a), let end = point(b) else { return }
                        var path = Path(); path.move(to: start)
                        let dx = max(50 * scale, abs(end.x - start.x) * 0.45)
                        path.addCurve(to: end, control1: .init(x: start.x + dx, y: start.y), control2: .init(x: end.x - dx, y: end.y))
                        context.stroke(path, with: .color(color), style: .init(lineWidth: 1.2, dash: dash))
                        if arrow {
                            let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                            let angle = atan2(end.y - start.y, end.x - start.x - dx)
                            var head = Path()
                            head.move(to: CGPoint(x: center.x - 7 * cos(angle - 0.5), y: center.y - 7 * sin(angle - 0.5)))
                            head.addLine(to: center)
                            head.addLine(to: CGPoint(x: center.x - 7 * cos(angle + 0.5), y: center.y - 7 * sin(angle + 0.5)))
                            context.stroke(head, with: .color(color), lineWidth: 1.4)
                        }
                    }
                    for skill in skills { if let parent = skill.parentSkillId { edge(parent, skill.id, color: .white.opacity(0.22), dash: [], arrow: false) } }
                    for link in links {
                        edge(link.linkType == .prerequisite ? link.toSkillId : link.fromSkillId, link.linkType == .prerequisite ? link.fromSkillId : link.toSkillId, color: link.linkType == .prerequisite ? AtlasTheme.growth.opacity(0.65) : .white.opacity(0.35), dash: link.linkType == .prerequisite ? [7, 5] : [2, 6], arrow: link.linkType == .prerequisite)
                    }
                }.allowsHitTesting(false)
                ForEach(skills) { skill in
                    if let point = model.positions[skill.id] {
                        SkillGraphNode(skill: skill, progress: progress.first { $0.skillId == skill.id }, selected: selected == skill.id) { select(skill.id) }
                            .frame(width: 184, height: 140).scaleEffect(scale)
                            .position(graphScreen(point, size: geometry.size, scale: scale, model: model, offset: offset))
                    }
                }
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 14) {
                            legend("层级", color: .white.opacity(0.45), dash: [])
                            legend("前置", color: AtlasTheme.growth.opacity(0.65), dash: [7, 5])
                            legend("关联", color: .white.opacity(0.45), dash: [2, 6])
                        }
                        Spacer()
                        HStack(spacing: 14) {
                            Button { zoom(by: 0.8) } label: { Image(systemName: "minus.magnifyingglass") }.help("缩小")
                            Text("\(Int(viewport.scale * 100))%").font(.caption).monospacedDigit().frame(width: 40)
                            Button { zoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.help("放大")
                            Button("适合窗口") { fit(geometry.size) }
                        }.buttonStyle(.borderless)
                    }.padding(16).background(AtlasTheme.ground.opacity(0.94))
                }
            }.clipped().contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6).updating($drag) { value, state, _ in state = value.translation }.onEnded { value in viewport.offset.width += value.translation.width; viewport.offset.height += value.translation.height })
                .simultaneousGesture(MagnificationGesture().updating($magnify) { value, state, _ in state = value }.onEnded { value in viewport.scale = min(2, max(0.3, viewport.scale * value)) })
                .onAppear { if !viewport.initialized { fit(geometry.size) }; if let focusRequest { focus(focusRequest, size: geometry.size) } }
                .onChange(of: geometry.size) { _, size in if !viewport.initialized { fit(size) } }
                .onChange(of: focusRequest) { _, id in if let id { focus(id, size: geometry.size) } }
                .onChange(of: skills.map(\.id)) { old, _ in if old.isEmpty { fit(geometry.size) } }
        }
    }
    private func legend(_ title: String, color: Color, dash: [CGFloat]) -> some View {
        HStack(spacing: 5) {
            Path { path in path.move(to: .init(x: 0, y: 2)); path.addLine(to: .init(x: 24, y: 2)) }
                .stroke(color, style: .init(lineWidth: 1.2, dash: dash)).frame(width: 24, height: 4).accessibilityHidden(true)
            Text(title)
        }.font(.caption2).foregroundStyle(AtlasTheme.muted)
    }
    private func zoom(by multiplier: CGFloat) { viewport.scale = min(2, max(0.3, viewport.scale * multiplier)) }
    private func fit(_ size: CGSize) {
        guard size.width > 0, size.height > 64 else { return }
        viewport = .init(scale: min(1, max(0.3, min(size.width / layout.width, (size.height - 64) / layout.height))), initialized: true)
    }
    private func focus(_ id: String, size: CGSize) {
        guard let point = layout.positions[id] else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            viewport.scale = max(0.8, viewport.scale)
            viewport.offset = .init(width: -(point.x - layout.width / 2) * viewport.scale - min(120, size.width * 0.15), height: -(point.y - layout.height / 2) * viewport.scale)
        }
    }
}

private struct SkillGraphNode: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skill: SkillRecord
    let progress: SkillProgress?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @State private var levelGain: Int64 = 0
    private var locked: Bool { progress?.unlocked == false }
    private var prerequisiteHint: String {
        let missing = progress?.missingPrerequisites ?? []
        return missing.map { "\($0.name)：Lv.\($0.currentLevel) / \($0.requiredLevel)，还差 \(max(0, $0.requiredLevel - $0.currentLevel)) 级" }.joined(separator: "；")
    }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle().fill(AtlasTheme.surface).frame(width: 56, height: 56)
                        Circle().stroke(AtlasTheme.raised, lineWidth: 3).frame(width: 60, height: 60)
                        Circle().trim(from: 0, to: Double(progress?.xpCurrent ?? 0) / Double(max(1, progress?.xpRequired ?? 60)))
                            .stroke(AtlasTheme.growth, style: .init(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 60, height: 60)
                        Image(systemName: SkillIcon.find(skill.iconKey).symbol).font(.system(size: 23, weight: .light)).foregroundStyle(locked ? AtlasTheme.muted : .white)
                    }
                    if locked { Image(systemName: "lock.open").font(.system(size: 10)).padding(4).background(AtlasTheme.ground, in: Circle()).foregroundStyle(AtlasTheme.muted) }
                }
                Text(skill.name).font(.system(size: 13, weight: selected ? .semibold : .medium)).lineLimit(1)
                Text(skill.archivedAt != nil ? "已归档" : "Lv.\(progress?.level ?? 1) · 可练习").font(.system(size: 11)).foregroundStyle((progress?.level ?? 1) > 1 ? AtlasTheme.growth : AtlasTheme.muted)
                if locked { Text("前置条件未满足").font(.system(size: 11)).foregroundStyle(AtlasTheme.muted) }
            }.frame(maxWidth: .infinity).padding(8).background(selected || hovering ? AtlasTheme.raised.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).onHover { hovering = $0 }.help(prerequisiteHint.isEmpty ? "\(skill.name) · 点击查看详情" : "\(skill.name) · 可继续专注\n\(prerequisiteHint)")
            .overlay(alignment: .topTrailing) { if levelGain > 0 { Text("+\(levelGain) 级").font(.caption.weight(.medium)).foregroundStyle(AtlasTheme.growth).padding(4).background(AtlasTheme.ground).transition(.opacity) } }
            .onChange(of: progress?.level) { old, new in
                guard let old, let new, new > old else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { levelGain = new - old }
                Task { try? await Task.sleep(for: .seconds(2)); withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { levelGain = 0 } }
            }
            .accessibilityLabel("\(skill.name)，等级 \(progress?.level ?? 1)，\(locked ? "前置条件未满足，可继续专注" : "可练习")")
            .accessibilityHint(prerequisiteHint.isEmpty ? "打开技能详情" : prerequisiteHint)
    }
}

nonisolated private func graphScreen(_ point: GraphPosition, size: CGSize, scale: CGFloat, model: SkillGraphLayout, offset: CGSize) -> CGPoint {
    .init(x: (point.x - model.width / 2) * scale + size.width / 2 + offset.width, y: (point.y - model.height / 2) * scale + size.height / 2 + offset.height)
}
