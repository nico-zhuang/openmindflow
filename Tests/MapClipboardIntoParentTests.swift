import AppKit

@main enum MapClipboardIntoParentTests {
    static func main() throws {
        let descendant = MapNode(id: UUID(), title: "descendant", children: [], folded: false,
                                 location: SIMD2(940, 180))
        let first = MapNode(id: UUID(), title: "first", children: [descendant], folded: false,
                            location: SIMD2(800, 160), rootShape: "rounded",
                            rootFillColor: "#FF335577")
        let second = MapNode(id: UUID(), title: "second", children: [], folded: false,
                             location: SIMD2(800, 270))
        let existing = MapNode(id: UUID(), title: "existing", children: [], folded: false)
        let leftParent = MapNode(id: UUID(), title: "left parent", children: [existing], folded: true,
                                 location: SIMD2(-300, 200), branchSide: "left")
        let destination = MapNode(id: UUID(), title: "destination", children: [leftParent], folded: false,
                                  location: SIMD2(100, 200))
        let link = MapRelationship(id: UUID(), from: descendant.id, to: second.id,
                                   control1: SIMD2(60, -25), control2: SIMD2(-50, 25),
                                   style: .dashed, startArrow: true, endArrow: false)
        let model = MapModel(roots: [destination, first, second], selected: first.id)
        model.relationships = [link]
        assert(model.selectNodes([first.id, second.id]), "Select both independent source branches")
        let clip = try unwrap(model.copySelection())
        assert(clip.roots.map(\.id) == [first.id, second.id], "Copy retains source sibling order")
        assert(clip.relationships.map(\.id) == [link.id], "Copy retains internal cross-branch edge")
        assert(model.selectOnly(leftParent.id), "Select the destination parent")
        let before = model.roots, edgesBefore = model.relationships
        let selectionBefore = model.selectedIDs
        assert(model.pasteSelection(clip, at: CGPoint(x: -300, y: 200), into: leftParent.id),
               "Pasting onto a selected node appends both branches as children")
        assert(model.roots.count == 3 && model.roots[1...2] == before[1...2],
               "Parent paste must not add independent roots or alter source trees")
        let parent = model.roots[0].children[0]
        assert(!parent.folded && parent.children.count == 3 && parent.children[0] == existing,
               "Pasting expands destination and keeps existing children before the copied group")
        let copiedFirst = parent.children[1], copiedSecond = parent.children[2]
        assert([copiedFirst.title, copiedSecond.title] == ["first", "second"]
               && copiedFirst.children.map(\.title) == ["descendant"],
               "Top-level grouping, order, and descendants survive")
        let newIDs = [copiedFirst.id, copiedSecond.id, copiedFirst.children[0].id]
        assert(Set(newIDs).count == 3 && Set(newIDs).isDisjoint(with: [first.id, second.id, descendant.id]),
               "All descendants and top-level nodes receive fresh IDs")
        assert(copiedFirst.location == nil && copiedSecond.location == nil
               && copiedFirst.children[0].location == nil && copiedFirst.branchSide == nil
               && copiedFirst.rootShape == nil && copiedFirst.rootFillColor == nil,
               "Child paste discards absolute positions and root-only appearance")
        assert(model.selectedIDs == Set([copiedFirst.id, copiedSecond.id])
               && model.selected == copiedFirst.id, "Only the newly pasted top-level children are selected")
        assert(model.relationships.count == 2 && model.relationships[0] == link
               && model.relationships[1].id != link.id
               && model.relationships[1].from == copiedFirst.children[0].id
               && model.relationships[1].to == copiedSecond.id,
               "Internal relationship gets fresh identity and cloned endpoints")
        let frames = Dictionary(uniqueKeysWithValues: mapLayout(model.roots).map { ($0.node.id, $0.frame) })
        let parentFrame = frames[parent.id]!, firstFrame = frames[copiedFirst.id]!
        let secondFrame = frames[copiedSecond.id]!, existingFrame = frames[existing.id]!
        assert(firstFrame.maxX < parentFrame.minX && secondFrame.maxX < parentFrame.minX
               && frames[copiedFirst.children[0].id]!.maxX < firstFrame.minX,
               "A paste into a left branch lays descendants out to the left")
        assert(!firstFrame.intersects(parentFrame) && !secondFrame.intersects(parentFrame)
               && !firstFrame.intersects(existingFrame) && !secondFrame.intersects(existingFrame)
               && !firstFrame.intersects(secondFrame),
               "Automatic child placement does not stack copies atop parent or siblings")
        let pasted = model.roots, pastedEdges = model.relationships
        assert(model.undo() && model.roots == before && model.relationships == edgesBefore
               && model.selectedIDs == selectionBefore && model.selected == leftParent.id,
               "One Undo restores tree, links, folded state, and selection")
        assert(!model.undo(), "Pasting multiple children must create just one Undo entry")
        assert(model.redo() && model.roots == pasted && model.relationships == pastedEdges
               && model.selectedIDs == Set([copiedFirst.id, copiedSecond.id]),
               "One Redo restores the entire child group")
        let lastRoots = model.roots, lastEdges = model.relationships
        let lastSelection = model.selectedIDs
        assert(!model.pasteSelection(clip, at: .zero, into: UUID())
               && model.roots == lastRoots && model.relationships == lastEdges
               && model.selectedIDs == lastSelection,
               "Missing parent must fail without changing tree, links, or selection")
        assert(model.undo() && model.roots == before && model.relationships == edgesBefore,
               "Invalid parent must not add another Undo entry")
        assert(model.redo() && model.roots == pasted, "Invalid paste must preserve Redo")

        // Both sides fit the per-document limit separately, but their combination cannot be saved.
        let largeTitle = String(repeating: "x", count: 65_000)
        let existingLarge = (0..<260).map { _ in
            MapNode(id: UUID(), title: largeTitle, children: [], folded: false)
        }
        let largeParent = MapNode(id: UUID(), title: "target", children: existingLarge, folded: false)
        let largeModel = MapModel(roots: [largeParent], selected: largeParent.id)
        let largeClip = MapSelectionClip(roots: (0..<260).map { _ in
            MapNode(id: UUID(), title: largeTitle, children: [], folded: false,
                    location: SIMD2(800, 300))
        }, relationships: [])
        let largeBefore = largeModel.roots
        assert(!largeModel.pasteSelection(largeClip, at: .zero, into: largeParent.id)
               && largeModel.roots == largeBefore && largeModel.selectedIDs == [largeParent.id]
               && !largeModel.undo(),
               "Too-large combined document fails atomically without adding Undo history")
        let leftSource = MapNode(id: UUID(), title: "copied left", children: [], folded: false,
                                 branchSide: "left")
        let primary = MapNode(id: UUID(), title: "main", children: [leftSource], folded: false)
        let leftModel = MapModel(roots: [primary], selected: leftSource.id)
        let sourceFrame = mapLayout(leftModel.roots).first { $0.node.id == leftSource.id }!.frame
        let leftClip = try unwrap(leftModel.copySelection(visibleCenters: [leftSource.id:
            CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)]))
        assert(leftModel.selectOnly(primary.id))
        let leftBefore = leftModel.roots
        assert(leftModel.pasteSelection(leftClip, at: .zero, into: primary.id))
        let clonedLeft = leftModel.roots[0].children.last!
        let leftFrames = Dictionary(uniqueKeysWithValues: mapLayout(leftModel.roots).map { ($0.node.id, $0.frame) })
        assert(clonedLeft.id != leftSource.id && clonedLeft.branchSide == "left" &&
               leftFrames[clonedLeft.id]!.maxX < leftFrames[primary.id]!.minX,
               "Pasting an explicitly left first-level child into a root retains its left branch side")
        assert(leftModel.undo() && leftModel.roots == leftBefore && !leftModel.undo(),
               "The first-level left paste is exactly one Undoable change")
        print("multi-root child clipboard, layout, left branch, remap, atomic Undo/Redo and failures passed")
    }
}

private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "copySelection returned nil", code: 1) }
    return value
}
