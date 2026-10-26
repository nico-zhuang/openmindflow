import AppKit

@main
enum LayoutTests {
    static func main() throws {
        assert(mapFont(isRoot: true).pointSize == 24)
        assert(mapFont(isRoot: false).pointSize == 20)
        assert(mapFont(isRoot: true) != mapFont(isRoot: false))
        let fontRoot = MapNode(id: UUID(), title: "Preview", children: [], folded: false)
        var largerRoot = fontRoot
        largerRoot.fontFamily = "Helvetica"
        largerRoot.fontSize = 80
        assert(mapLayout([largerRoot])[0].frame.height > mapLayout([fontRoot])[0].frame.height + 40,
               "Edited font size must affect own JSON layout even with no imported metadata")
        var notedRoot = MapNode(id: UUID(), title: String(repeating: "a ", count: 40), children: [], folded: false)
        notedRoot.width = 170
        notedRoot.note = "Visible note"
        let notedFrame = mapLayout([notedRoot])[0].frame
        let notedText = (notedRoot.title as NSString).boundingRect(
            with: CGSize(width: notedFrame.width - 48, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: mapFont(isRoot: true, node: notedRoot)])
        assert(ceil(notedText.height) <= notedFrame.height - 22,
               "A noted root must reserve its paper-icon width when computing title height")
        let importedFont = NSFont.systemFont(ofSize: 36)
        let importedOverride = MapLayoutOverride(location: nil, maxWidth: 170,
                                                 allowToShrinkWidth: false, font: importedFont)
        let importedFrame = mapLayout([notedRoot], overrides: [notedRoot.id: importedOverride])[0].frame
        let importedText = (notedRoot.title as NSString).boundingRect(
            with: CGSize(width: importedFrame.width - 48, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: importedFont])
        assert(ceil(importedText.height) <= importedFrame.height - 22,
               "Imported root font override must also reserve note width")
        var withoutNote = notedRoot
        withoutNote.note = nil
        let plainFrame = mapLayout([withoutNote])[0].frame
        let plainText = (withoutNote.title as NSString).boundingRect(
            with: CGSize(width: plainFrame.width - 24, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: mapFont(isRoot: true, node: withoutNote)])
        assert(plainFrame.height == max(44, ceil(plainText.height) + 22),
               "Note-free root retains original sizing")
        let root = MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "First", children: [], folded: false),
            MapNode(id: UUID(), title: "Second", children: [], folded: true)
        ], folded: false)
        let secondRoot = MapNode(id: UUID(), title: "Other", children: [], folded: false)
        let single = mapLayout([MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "Only child", children: [], folded: false)
        ], folded: false)])
        assert(abs(single[0].frame.midY - (single[1].frame.maxY - 7)) < 0.01,
               "The first child's underline must meet the root center without bending the new branch")
        let short = MapNode(id: UUID(), title: "Short", children: [
            MapNode(id: UUID(), title: "Leaf", children: [], folded: false)
        ], folded: false)
        let tall = MapNode(id: UUID(), title: "Tall", children: [
            MapNode(id: UUID(), title: String(repeating: "Multiline child\n", count: 16),
                    children: [], folded: false)
        ], folded: false)
        let stacked = mapLayout([short, tall])
        assert(!stacked[1].frame.intersects(stacked[3].frame),
               "Straight single-child branches must reserve their headroom so separate root trees cannot collide")
        let roots = [root, secondRoot]
        let first = mapLayout(roots)
        assert(first.map(\.frame) == mapLayout(roots).map(\.frame), "Layout must be deterministic")
        assert(first.map(\.frame) == [CGRect(x: 0, y: 34.5, width: 170, height: 55),
                                     CGRect(x: 230, y: 0, width: 170, height: 50),
                                     CGRect(x: 230, y: 74, width: 170, height: 50),
                                     CGRect(x: 0, y: 148, width: 170, height: 55)],
               "Default all-right frames must retain exact legacy coordinates: \(first.map(\.frame))")
        assert(first.map(\.node.id) == [root.id, root.children[0].id, root.children[1].id, secondRoot.id])
        assert(first[1].frame.maxY < first[2].frame.minY, "Children must not overlap")
        assert(first[2].frame.minY - first[1].frame.maxY == 24,
               "New auto-layout siblings should have a tighter 24pt default gap")
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
        let nativeRoot = MapNode(id: UUID(), title: "Native root", children: [
            MapNode(id: UUID(), title: "New child", children: [], folded: false),
            MapNode(id: UUID(), title: String(repeating: "wide content ", count: 20), children: [], folded: false),
            MapNode(id: UUID(), title: "Explicit width", children: [], folded: false, width: 136)
        ], folded: false, width: 316)
        let distantRoot = MapNode(id: UUID(), title: "Distant", children: [], folded: false)
        let nativeRoots = [nativeRoot, distantRoot]
        let defaults = Dictionary(uniqueKeysWithValues: mapLayout(nativeRoots).map { ($0.node.id, $0.frame) })
        let overrides: [UUID: MapLayoutOverride] = [
            nativeRoot.id: MapLayoutOverride(location: CGPoint(x: -900, y: 1200), maxWidth: 240,
                                             allowToShrinkWidth: false, font: .systemFont(ofSize: 36)),
            nativeRoot.children[1].id: MapLayoutOverride(location: nil, maxWidth: 180,
                                                          allowToShrinkWidth: true, font: .systemFont(ofSize: 24)),
            nativeRoot.children[2].id: MapLayoutOverride(location: nil, maxWidth: 80,
                                                          allowToShrinkWidth: false, font: nil),
            distantRoot.id: MapLayoutOverride(location: CGPoint(x: 1500, y: -750), maxWidth: 136,
                                               allowToShrinkWidth: false, font: nil)
        ]
        let native = Dictionary(uniqueKeysWithValues: mapLayout(nativeRoots, overrides: overrides).map { ($0.node.id, $0.frame) })
        let rootFrame = native[nativeRoot.id]!
        let distantFrame = native[distantRoot.id]!
        assert(rootFrame.width == 316 && rootFrame.midX == -900 && rootFrame.midY == 1200)
        assert(distantFrame.width == 136 && distantFrame.midX == 1500 && distantFrame.midY == -750)
        assert(native[nativeRoot.children[1].id]!.width == 180, "Auto width must cap at native maxWidth")
        assert(native[nativeRoot.children[2].id]!.width == 136, "Explicit node.width wins")
        for child in nativeRoot.children {
            let actual = native[child.id]!, original = defaults[child.id]!, originalParent = defaults[nativeRoot.id]!
            assert(actual.midX - rootFrame.midX == original.midX - originalParent.midX)
            assert(actual.midY - rootFrame.midY == original.midY - originalParent.midY)
        }
        let rootText = (nativeRoot.title as NSString).boundingRect(
            with: CGSize(width: rootFrame.width - 24, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 36)])
        assert(rootFrame.height == max(44, ceil(rootText.height) + 22))
        let capped = native[nativeRoot.children[1].id]!
        let cappedText = (nativeRoot.children[1].title as NSString).boundingRect(
            with: CGSize(width: capped.width - 24, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 24)])
        assert(capped.height == max(44, ceil(cappedText.height) + 22))
        assert(nativeRoot.children.allSatisfy { dropPlacement(at: CGPoint(x: native[$0.id]!.midX, y: native[$0.id]!.midY), over: LaidOutNode(node: $0, frame: native[$0.id]!, parent: nativeRoot.id), siblings: [])?.parent == $0.id })
        let nested = MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "Pinned child", children: [
                MapNode(id: UUID(), title: "New grandchild", children: [], folded: false)
            ], folded: false),
            MapNode(id: UUID(), title: "Tiny", children: [], folded: false)
        ], folded: false)
        let nestedDefault = Dictionary(uniqueKeysWithValues: mapLayout([nested]).map { ($0.node.id, $0.frame) })
        let nestedOverrides: [UUID: MapLayoutOverride] = [
            nested.id: MapLayoutOverride(location: CGPoint(x: -100, y: 80), maxWidth: nil,
                                         allowToShrinkWidth: true, font: nil),
            nested.children[0].id: MapLayoutOverride(location: CGPoint(x: 300, y: 900), maxWidth: nil,
                                                     allowToShrinkWidth: false, font: nil),
            nested.children[1].id: MapLayoutOverride(location: nil, maxWidth: 20,
                                                     allowToShrinkWidth: true, font: nil)
        ]
        let nestedFrames = Dictionary(uniqueKeysWithValues: mapLayout([nested], overrides: nestedOverrides).map { ($0.node.id, $0.frame) })
        let pinned = nestedFrames[nested.children[0].id]!, grandchild = nestedFrames[nested.children[0].children[0].id]!
        assert(pinned.midX == 300 && pinned.midY == 900)
        assert(grandchild.midX - pinned.midX == nestedDefault[nested.children[0].children[0].id]!.midX - nestedDefault[nested.children[0].id]!.midX)
        assert(grandchild.midY - pinned.midY == nestedDefault[nested.children[0].children[0].id]!.midY - nestedDefault[nested.children[0].id]!.midY)
        assert(nestedFrames[nested.children[1].id]!.width == 60)
        print("layout and JSON roundtrip tests passed")
    }
}
