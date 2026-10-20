import Foundation

@main
enum LayoutTests {
    static func main() throws {
        let root = MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "First", children: [], folded: false),
            MapNode(id: UUID(), title: "Second", children: [], folded: true)
        ], folded: false)
        let secondRoot = MapNode(id: UUID(), title: "Other", children: [], folded: false)
        let roots = [root, secondRoot]
        let first = mapLayout(roots)
        assert(first.map(\.frame) == mapLayout(roots).map(\.frame), "Layout must be deterministic")
        assert(first.map(\.node.id) == [root.id, root.children[0].id, root.children[1].id, secondRoot.id])
        assert(first[1].frame.maxY < first[2].frame.minY, "Children must not overlap")
        assert(first[1].frame.minX == first[2].frame.minX)
        assert(first[0].frame.maxX < first[1].frame.minX)
        assert(first[2].frame.maxY < first[3].frame.minY, "Roots must not overlap")
        var folded = root
        folded.folded = true
        assert(mapLayout([folded]).map(\.node.id) == [root.id])
        assert(mapLayout([]).isEmpty)

        let decoded = try JSONDecoder().decode([MapNode].self, from: JSONEncoder().encode(roots))
        assert(decoded.map(\.id) == roots.map(\.id))
        assert(decoded.map(\.title) == roots.map(\.title))
        assert(decoded[0].children.map(\.id) == root.children.map(\.id))
        assert(decoded[0].children.map(\.title) == root.children.map(\.title))
        assert(decoded[0].children[1].folded)
        let siblingFrames = first.filter { $0.parent == root.id }
        let upper = first[1]
        let lower = first[2]
        let above = dropPlacement(at: CGPoint(x: upper.frame.midX, y: upper.frame.minY + 2), over: upper, siblings: siblingFrames)
        assert(above?.parent == root.id && above?.index == 0)
        let below = dropPlacement(at: CGPoint(x: lower.frame.midX, y: lower.frame.maxY - 2), over: lower, siblings: siblingFrames)
        assert(below?.parent == root.id && below?.index == 2)
        let child = dropPlacement(at: CGPoint(x: upper.frame.midX, y: upper.frame.midY), over: upper, siblings: siblingFrames)
        assert(child?.parent == upper.node.id && child?.index == 0)
        assert(dropPlacement(at: first[0].frame.origin, over: first[0], siblings: []) == nil)
        print("layout and JSON roundtrip tests passed")
    }
}
