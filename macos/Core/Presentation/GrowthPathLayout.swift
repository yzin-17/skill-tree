import Foundation

public struct GrowthPathLayout: Sendable {
    public struct Node: Sendable {
        public let id: String
        public let parentID: String?
        public let name: String
        public let order: Int
        public init(id: String, parentID: String? = nil, name: String, order: Int = 0) {
            self.id = id; self.parentID = parentID; self.name = name; self.order = order
        }
    }
    public struct Edge: Sendable, Equatable {
        public let parent: String
        public let child: String
    }
    public static let nodeWidth = 220.0
    public static let nodeHeight = 144.0
    public let positions: [String: GraphPosition]
    public let orderedIDs: [String]
    public let edges: [Edge]
    public let width: Double
    public let height: Double

    public init(nodes: [Node]) {
        let sorted = nodes.sorted { ($0.order, $0.name, $0.id) < ($1.order, $1.name, $1.id) }
        let byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [String: [Node]] = [:]
        for node in sorted where byID[node.id]?.parentID == node.parentID {
            if let parent = node.parentID, parent != node.id, byID[parent] != nil {
                children[parent, default: []].append(node)
            }
        }
        var visited = Set<String>(), positions: [String: GraphPosition] = [:]
        var ids: [String] = [], edges: [Edge] = []
        var nextRow = 16.0 + Self.nodeHeight / 2
        func place(_ node: Node, depth: Int) {
            guard visited.insert(node.id).inserted else { return }
            ids.append(node.id)
            var childRows: [Double] = []
            for child in children[node.id] ?? [] where !visited.contains(child.id) {
                edges.append(.init(parent: node.id, child: child.id))
                place(child, depth: depth + 1)
                if let position = positions[child.id] { childRows.append(position.y) }
            }
            let y: Double
            if let first = childRows.first, let last = childRows.last { y = (first + last) / 2 }
            else { y = nextRow; nextRow += Self.nodeHeight + 32 }
            positions[node.id] = .init(x: 16 + Self.nodeWidth / 2 + Double(depth) * (Self.nodeWidth + 56), y: y)
        }
        let roots = sorted.filter { $0.parentID == nil || $0.parentID == $0.id || byID[$0.parentID ?? ""] == nil }
        for node in roots + sorted where !visited.contains(node.id) {
            place(node, depth: 0)
            nextRow += 16
        }
        self.positions = positions; orderedIDs = ids; self.edges = edges
        width = positions.values.map(\.x).max().map { $0 + Self.nodeWidth / 2 + 16 } ?? 0
        height = positions.values.map(\.y).max().map { $0 + Self.nodeHeight / 2 + 16 } ?? 0
    }
}
