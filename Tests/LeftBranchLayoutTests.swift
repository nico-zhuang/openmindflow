import AppKit

@main
enum LeftBranchLayoutTests {
    static func main() {
        func node(_ title: String, children: [MapNode] = [], side: String? = nil, folded: Bool = false) -> MapNode {
            MapNode(id: UUID(), title: title, children: children, folded: folded, branchSide: side)
        }
        let leftA = node("Left A", children: [node("Left grandchild")], side: "left")
        let leftB = node("Left B", side: "left")
        let rightA = node("Right A", children: [node("Right grandchild")])
        let rightB = node("Right B", side: "right")
        let root = node("Root", children: [leftA, rightA, leftB, rightB])
        let second = node("Second root", children: [node("Hidden", side: "left")], folded: true)
        let laid = mapLayout([root, second])
        let frames = Dictionary(uniqueKeysWithValues: laid.map { ($0.node.id, $0.frame) })
        assert(laid.map(\.frame) == mapLayout([root, second]).map(\.frame), "Mixed layout is deterministic")
        assert(laid.map(\.node.id) == [root.id, leftA.id, leftA.children[0].id,
                                         rightA.id, rightA.children[0].id, leftB.id, rightB.id, second.id])
        assert(frames[leftA.id]!.maxX <= frames[root.id]!.minX - 60)
        assert(frames[leftA.children[0].id]!.maxX <= frames[leftA.id]!.minX - 60)
        assert(frames[rightA.id]!.minX >= frames[root.id]!.maxX + 60)
        assert(frames[leftA.id]!.maxY + 24 <= frames[leftB.id]!.minY)
        assert(frames[rightA.id]!.maxY + 24 <= frames[rightB.id]!.minY)
        assert(laid.dropLast().allSatisfy { $0.frame.maxY < frames[second.id]!.minY })
        assert(!laid.contains { $0.node.id == second.children[0].id })
        let leftOnly = node("Standalone left", children: [node("Only left", side: "left")])
        let leftOnlyFrames = Dictionary(uniqueKeysWithValues: mapLayout([leftOnly, second]).map { ($0.node.id, $0.frame) })
        assert(leftOnlyFrames[leftOnly.children[0].id]!.maxX <= leftOnlyFrames[leftOnly.id]!.minX - 60)
        assert(leftOnlyFrames[leftOnly.children[0].id]!.maxY < leftOnlyFrames[second.id]!.minY)
        assert(abs(leftOnlyFrames[leftOnly.id]!.midY - (leftOnlyFrames[leftOnly.children[0].id]!.maxY - 7)) < 0.01,
               "A sole left branch must meet the root center at its straight underline")

        let tallLeftGrandchild = node(String(repeating: "Tall grandchild\n", count: 24))
        let tallLeftChild = node(String(repeating: "Tall left child\n", count: 16),
                                 children: [tallLeftGrandchild], side: "left")
        let tallLeftRoot = node("Tall left root", children: [tallLeftChild])
        let followingRoot = node("Following root")
        let tallLaid = mapLayout([tallLeftRoot, followingRoot])
        let tallFrames = Dictionary(uniqueKeysWithValues: tallLaid.map { ($0.node.id, $0.frame) })
        assert(tallFrames[tallLeftChild.id]!.height > tallFrames[tallLeftRoot.id]!.height * 3 &&
               tallFrames[tallLeftGrandchild.id]!.height > tallFrames[tallLeftChild.id]!.height,
               "This case must exercise a tall child and taller grandchild")
        assert(abs(tallFrames[tallLeftRoot.id]!.midY - (tallFrames[tallLeftChild.id]!.maxY - 7)) < 0.01,
               "Even a tall left subtree must retain the straight first-branch baseline")
        assert(tallLaid.dropLast().allSatisfy { $0.frame.minY >= 0 && $0.frame.maxY + 24 <= tallFrames[followingRoot.id]!.minY },
               "Straight left headroom must preserve the entire subtree and the next root")

        let rightOnly = node("Root", children: [node("Only child")])
        let rightOnlyFrames = mapLayout([rightOnly]).map(\.frame)
        assert(rightOnlyFrames == [CGRect(x: 0, y: 15.5, width: 170, height: 55),
                                   CGRect(x: 230, y: 0, width: 170, height: 50)],
               "All-right legacy coordinates must remain unchanged")

        // Native presentation coordinates are authoritative until an explicit model-side switch.
        let originalLeft = node("Imported left", children: [node("Imported descendant")])
        let originalRight = node("Imported right")
        let sibling = node("Imported sibling")
        let importedRoot = node("Oversized native root", children: [originalLeft, originalRight, sibling])
        let otherRoot = node("Unrelated imported root")
        let model = MapModel(roots: [importedRoot, otherRoot], selected: originalLeft.id)
        model.roots[0].children[0].location = SIMD2(1550, 210)
        model.roots[0].children[0].children[0].location = SIMD2(1800, 230)
        func presentation(_ x: CGFloat, _ y: CGFloat, width: CGFloat? = nil) -> MapLayoutOverride {
            MapLayoutOverride(location: CGPoint(x: x, y: y), maxWidth: width,
                              allowToShrinkWidth: false, font: nil)
        }
        let overrides: [UUID: MapLayoutOverride] = [
            importedRoot.id: presentation(1000, 400, width: 640),
            originalLeft.id: presentation(1500, 200),
            originalLeft.children[0].id: presentation(1750, 220),
            originalRight.id: presentation(1700, 500),
            sibling.id: presentation(1900, 700),
            otherRoot.id: presentation(-1300, -800)
        ]
        func placed() -> [UUID: CGRect] {
            Dictionary(uniqueKeysWithValues: mapLayout(model.roots, overrides: overrides).map { ($0.node.id, $0.frame) })
        }
        let before = placed()
        assert(before[originalLeft.id]!.midX == 1550 && before[originalLeft.children[0].id]!.midX == 1800,
               "Saved MapNode centers outrank native presentation until an explicit switch")
        assert(before[originalRight.id]!.midX == 1700 && before[sibling.id]!.midX == 1900)
        assert(before[importedRoot.id]!.width == 640 && before[otherRoot.id]!.midX == -1300)
        assert(model.setRootBranchSide("left", for: originalLeft.id))
        let left = placed()
        assert(left[originalLeft.id]!.maxX <= left[importedRoot.id]!.minX - 60,
               "Explicit switch must ignore stale native child location and oversized root width")
        assert(left[originalLeft.children[0].id]!.maxX <= left[originalLeft.id]!.minX - 60,
               "Explicit switch must ignore stale native descendant location")
        assert(left[importedRoot.id] == before[importedRoot.id] && left[otherRoot.id] == before[otherRoot.id])
        assert(left[originalRight.id] == before[originalRight.id] && left[sibling.id] == before[sibling.id])
        assert(model.setRootBranchSide("right", for: originalRight.id))
        let right = placed()
        assert(right[originalRight.id]!.minX >= right[importedRoot.id]!.maxX + 60,
               "Explicit right switch must use actual oversized root edge, not center translation")
        assert(right[originalLeft.id] == left[originalLeft.id] && right[sibling.id] == before[sibling.id])
        // A later manual free move remains authoritative even though the stale presentation exists.
        model.roots[0].children[0].location = SIMD2(-900, 123)
        assert(placed()[originalLeft.id]!.midX == -900)
        print("mixed left/right layout, folds, imported coordinates and explicit switch tests passed")
    }
}
