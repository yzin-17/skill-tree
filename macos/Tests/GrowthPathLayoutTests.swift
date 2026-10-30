import Foundation
import Testing
@testable import SkillAtlasCore

struct GrowthPathLayoutTests {
    @Test func branchesStayInTheirOwnSubtreesAndOrderIsStable() {
        let nodes: [GrowthPathLayout.Node] = [
            .init(id: "root", name: "摄影"),
            .init(id: "portrait", parentID: "root", name: "人像", order: 1),
            .init(id: "light", parentID: "portrait", name: "布光"),
            .init(id: "street", parentID: "root", name: "街头", order: 2),
            .init(id: "other", name: "陶艺", order: 3)
        ]
        let layout = GrowthPathLayout(nodes: nodes)
        #expect(layout.orderedIDs == ["root", "portrait", "light", "street", "other"])
        #expect(layout.positions == GrowthPathLayout(nodes: nodes.reversed()).positions)
        #expect(layout.positions["portrait"]!.x == layout.positions["street"]!.x)
        #expect(layout.positions["street"]!.y - layout.positions["portrait"]!.y > GrowthPathLayout.nodeHeight)
        #expect(layout.positions["portrait"]!.y == layout.positions["light"]!.y)
        #expect(layout.positions["other"]!.y > layout.positions["street"]!.y)
        #expect(layout.edges.count == 3)
    }

    @Test func missingParentsAndCyclesKeepEveryNodeExactlyOnce() {
        let layout = GrowthPathLayout(nodes: [
            .init(id: "a", parentID: "b", name: "A"),
            .init(id: "b", parentID: "a", name: "B"),
            .init(id: "c", parentID: "missing", name: "C"),
            .init(id: "d", parentID: "d", name: "D")
        ])
        #expect(Set(layout.orderedIDs) == ["a", "b", "c", "d"])
        #expect(layout.orderedIDs.count == 4)
        #expect(layout.edges.count == 1)
        #expect(layout.edges.allSatisfy { layout.positions[$0.parent]!.x < layout.positions[$0.child]!.x })
    }

    @Test func emptyAndSingleNodeHaveNoInventedBranches() {
        let empty = GrowthPathLayout(nodes: [])
        #expect(empty.positions.isEmpty && empty.edges.isEmpty && empty.width == 0 && empty.height == 0)
        let single = GrowthPathLayout(nodes: [.init(id: "one", name: "兴趣方向中的一个很长的自定义成长阶段名称")])
        #expect(single.orderedIDs == ["one"] && single.edges.isEmpty)
        #expect(single.width == GrowthPathLayout.nodeWidth + 32)
        #expect(single.height == GrowthPathLayout.nodeHeight + 32)
    }

    @Test func historicalLabelsPreserveUserNamesAndUnrelatedEvents() {
        func event(_ type: String, _ summary: String) -> ActivityRecord {
            .init(id: "event", type: type, producer: "server", entityType: "career", entityId: "stage", summary: summary, skillIds: [], metadata: [:], occurredAt: .now, createdAt: .now)
        }
        #expect(AchievementDisplay.eventSummary(event("career.created", "创建职业阶段「职业兴趣探索」")) == "创建成长阶段「职业兴趣探索」")
        #expect(AchievementDisplay.eventSummary(event("career.transitioned", "确认职业转职")) == "进入成长阶段")
        #expect(AchievementDisplay.eventSummary(event("task.created", "创建职业阶段")) == "创建职业阶段")
    }
}
