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
        print("layout and JSON roundtrip tests passed")
    }
}
