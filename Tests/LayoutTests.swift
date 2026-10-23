import AppKit

@main
enum LayoutTests {
    static func main() throws {
        assert(mapFont(isRoot: true).pointSize == 20)
        assert(mapFont(isRoot: false).pointSize == 16)
        assert(mapFont(isRoot: true) != mapFont(isRoot: false))
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

        let longTitle = "这是一段需要自动换行的中文主题 🧠🌍 " + String(repeating: "extended label ", count: 9)
        let children = (0..<20).map { index -> MapNode in
            let title = index % 3 == 0 ? longTitle : index % 3 == 1 ? "想法 🎨\n第二行 🏗️" : "简短 \(index)"
            let grandchildren = index == 0
                ? [MapNode(id: UUID(), title: "Folded child must stay hidden", children: [], folded: false)]
                : (index % 2 == 1 && index < 17
                    ? [MapNode(id: UUID(), title: "子节点 🐼 \(index)", children: [], folded: false)] : [])
            return MapNode(id: UUID(), title: title, children: grandchildren, folded: index == 0)
        }
        let largeRoots = [MapNode(id: UUID(), title: "三十个节点 🌳", children: children, folded: false),
                          MapNode(id: UUID(), title: "第二主节点\n多行标题", children: [], folded: false)]
        let large = mapLayout(largeRoots)
        assert(large.count == 30, "Folded descendants must not take space")
        assert(!large.contains { $0.node.id == children[0].children[0].id })
        assert(large.map(\.frame) == mapLayout(largeRoots).map(\.frame), "Large map must lay out deterministically")
        assert(large.contains { $0.frame.width > 170 }, "Long titles must widen their nodes")
        assert(large.contains { $0.frame.height > 44 }, "Multiline titles must grow vertically")
        for (index, node) in large.enumerated() {
            for other in large.dropFirst(index + 1) {
                assert(!node.frame.intersects(other.frame), "Visible node frames must not overlap")
            }
            let text = node.node.folded && !node.node.children.isEmpty ? "▸ " + node.node.title : node.node.title
            let measured = ((text.isEmpty ? "New idea" : text) as NSString).boundingRect(
                with: CGSize(width: node.frame.width - 24, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: mapFont(isRoot: node.parent == nil)])
            assert(ceil(measured.height) <= node.frame.height - 22, "Text must fit the node's vertical inset")
        }

        let customJSON = try JSONSerialization.data(withJSONObject: [[
            "id": UUID().uuidString, "title": "Short", "children": [], "folded": false, "width": 240
        ]])
        let custom = try JSONDecoder().decode([MapNode].self, from: customJSON)
        assert(mapLayout(custom)[0].frame.width == 240,
               "A node's saved width must change only that node's drawn/layout width")
        let roundtrip = try JSONDecoder().decode([MapNode].self, from: JSONEncoder().encode(custom))
        assert(mapLayout(roundtrip)[0].frame.width == 240, "Node width must survive own JSON roundtrip")
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
