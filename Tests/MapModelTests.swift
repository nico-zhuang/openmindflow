import Foundation

@main
enum MapModelTests {
    static func main() {
        let root = UUID(), child = UUID(), gestureLeaf = UUID(), sibling = UUID()
        let gesture = MapModel(roots: [MapNode(id: root, title: "root", children: [
            MapNode(id: child, title: "child", children: [
                MapNode(id: gestureLeaf, title: "hidden leaf", children: [], folded: false)
            ], folded: true),
            MapNode(id: sibling, title: "sibling", children: [], folded: false,
                    location: SIMD2(320, 300))
        ], folded: false)], selected: child)
        let starting = gesture.roots
        let idNote = MapModel(roots: starting, selected: root)
        assert(idNote.setNote("child note", for: child) && idNote.roots[0].children[0].note == "child note" &&
               idNote.selected == root && !idNote.setNote("child note", for: child) &&
               !idNote.setNote(String(repeating: "界", count: 22_000), for: child) &&
               !idNote.setNote("missing", for: UUID()) && idNote.undo() && idNote.roots == starting &&
               !idNote.undo() && idNote.redo() && idNote.roots[0].children[0].note == "child note")
        assert(gesture.selectNodes([root, child]) && gesture.selected == child)
        assert(gesture.selectedIDs == [root, child])
        let centers: [UUID: CGPoint] = [root: CGPoint(x: 100, y: 100)]
        assert(!gesture.translateSelectedSubtrees(by: CGPoint(x: CGFloat.nan, y: 10), visibleCenters: centers))
        assert(gesture.translateSelectedSubtrees(by: CGPoint(x: 20, y: -30), visibleCenters: centers))
        assert(gesture.roots[0].location == SIMD2(120, 70))
        assert(gesture.roots[0].children[0].location == nil)
        assert(gesture.roots[0].children[0].children[0].location == nil,
               "Folded descendants without saved locations follow shifted parent when revealed")
        assert(gesture.roots[0].children[1].location == SIMD2(340, 270),
               "Selected ancestor moves all descendants exactly once")
        assert(gesture.undo() && gesture.roots == starting, "One undo restores full subtree")
        assert(gesture.redo() && gesture.roots[0].location == SIMD2(120, 70))
        let translatedRoots = gesture.roots
        assert(!gesture.translateSelectedSubtrees(by: CGPoint(x: 1_000_000, y: 0), visibleCenters: centers))
        assert(gesture.roots == translatedRoots, "Overflow rejects every descendant together")
        assert(!gesture.selectNodes([UUID()]) && gesture.selectedIDs == [root, child])
        assert(gesture.selectNodes([]) && gesture.selectedIDs.isEmpty && gesture.selected == child)
        assert(!gesture.translateSelectedSubtrees(by: CGPoint(x: 1, y: 1), visibleCenters: centers))
        for before in [false, true] {
            let blank = MapModel(roots: [], selected: UUID())
            blank.addSibling(before: before)
            assert(blank.roots.count == 1 && blank.selected == blank.roots[0].id,
                   "Return on an empty map must create a selectable main node")
            let firstID = blank.selected
            blank.undo()
            assert(blank.roots.isEmpty)
            blank.redo()
            assert(blank.roots.map(\.id) == [firstID] && blank.selected == firstID)
        }
        let first = UUID(), middle = UUID(), last = UUID()
        let manyRoots = MapModel(roots: [first, middle, last].map {
            MapNode(id: $0, title: "Root", children: [], folded: false)
        }, selected: middle)
        manyRoots.remove()
        assert(manyRoots.roots.map(\.id) == [first, last] && manyRoots.selected == last,
               "Removing a main node should select the next remaining root")
        manyRoots.undo()
        assert(manyRoots.roots.map(\.id) == [first, middle, last] && manyRoots.selected == middle)
        manyRoots.redo()
        manyRoots.remove()
        assert(manyRoots.roots.map(\.id) == [first] && manyRoots.selected == first)
        manyRoots.remove() // Never delete the sole remaining root.
        assert(manyRoots.roots.map(\.id) == [first])
        manyRoots.undo() // Rejected removal must not create an undo entry.
        assert(manyRoots.roots.map(\.id) == [first, last] && manyRoots.selected == last)
        let sizedID = UUID()
        let sized = MapModel(roots: [MapNode(id: sizedID, title: "Resized", children: [], folded: false)], selected: sizedID)
        assert(sized.setWidth(240) && sized.roots[0].width == 240)
        assert(!sized.setWidth(240) && !sized.setWidth(59) && !sized.setWidth(1001) && !sized.setWidth(.nan) && !sized.setWidth(.infinity) && !sized.setWidth(-.infinity),
               "No-op, non-finite, and out-of-range widths must never add history")
        assert(sized.undo() && sized.roots[0].width == nil)
        assert(sized.redo() && sized.roots[0].width == 240)
        assert(sized.setWidth(nil) && sized.roots[0].width == nil)
        assert(sized.setWidth(136) && sized.roots[0].width == 136)
        assert(try! JSONDecoder().decode([MapNode].self, from: JSONEncoder().encode(sized.roots))[0].width == 136)
        assert(!sized.setWidth(136) && !sized.setWidth(.nan) && !sized.setWidth(59) && !sized.setWidth(1001))
        assert(sized.undo() && sized.roots[0].width == nil, "Rejected widths must not push undo")
        assert(sized.redo() && sized.roots[0].width == 136)
        assert(sized.setWidth(316) && sized.roots[0].width == 316)
        assert(try! JSONDecoder().decode([MapNode].self, from: JSONEncoder().encode(sized.roots))[0].width == 316)
        assert(sized.setWidth(60) && sized.setWidth(1000))
        assert(sized.setWidth(nil) && sized.roots[0].width == nil)
        assert(sized.setFont(family: "STSongti-SC-Regular", size: 36))
        assert(sized.roots[0].fontFamily == "STSongti-SC-Regular" && sized.roots[0].fontSize == 36)
        assert(!sized.setFont(family: "", size: 36) && !sized.setFont(family: "STSongti-SC-Regular", size: 241) &&
               !sized.setFont(family: "STSongti-SC-Regular", size: .nan) &&
               !sized.setFont(family: "STSongti-SC-Regular", size: 36))
        assert(sized.undo() && sized.roots[0].fontFamily == nil && sized.roots[0].fontSize == nil)
        assert(sized.redo() && sized.roots[0].fontSize == 36)
        assert(try! JSONDecoder().decode([MapNode].self, from: JSONEncoder().encode(sized.roots)) == sized.roots)
        let alignedID = UUID()
        let aligned = MapModel(roots: [MapNode(id: alignedID, title: "fixed left", children: [], folded: false,
            location: SIMD2(500, 170))], selected: alignedID)
        assert(aligned.setWidth(180, anchoredFrom: 136))
        assert(aligned.roots[0].width == 180 && aligned.roots[0].location == SIMD2(522, 170))
        assert(aligned.undo() && aligned.roots[0].width == nil && aligned.roots[0].location == SIMD2(500, 170))
        let connectedLeaf = MapNode(id: UUID(), title: "leaf", children: [], folded: false, location: SIMD2(780, 170))
        let branch = MapNode(id: UUID(), title: "branch", children: [connectedLeaf], folded: false,
                             location: SIMD2(500, 170))
        let parent = MapNode(id: UUID(), title: "root", children: [branch], folded: false,
                             location: SIMD2(200, 170))
        let reflow = MapModel(roots: [parent], selected: parent.id)
        assert(reflow.resizeSelected(by: 80, visibleWidths: [parent.id: 170]))
        assert(reflow.roots[0].location == SIMD2(240, 170) &&
               reflow.roots[0].children[0].location == SIMD2(580, 170) &&
               reflow.roots[0].children[0].children[0].location == SIMD2(860, 170),
               "Widening a positioned parent keeps downstream branch gaps instead of reversing connectors")
        assert(reflow.undo() && reflow.roots == [parent], "One undo restores widths and all dependent world positions")
        reflow.selectOnly(parent.id)
        assert(reflow.toggleSelection(branch.id))
        assert(reflow.resizeSelected(by: 40, visibleWidths: [parent.id: 170, branch.id: 136]))
        assert(reflow.roots[0].children[0].location == SIMD2(560, 170) &&
               reflow.roots[0].children[0].children[0].location == SIMD2(860, 170),
               "Overlapping selection moves a child by parent delta plus its own anchored half delta only once")
        assert(reflow.undo() && reflow.roots == [parent])
        let shiftedChild = MapNode(id: UUID(), title: "nested", children: [], folded: false,
                                   location: SIMD2(120, 70))
        let shifting = MapNode(id: UUID(), title: "moving", children: [shiftedChild], folded: false,
                               location: SIMD2(100, 50))
        let stationary = MapNode(id: UUID(), title: "target", children: [], folded: false,
                                 location: SIMD2(300, 100))
        let placedRoot = MapNode(id: UUID(), title: "root", children: [shifting, stationary], folded: false,
                                 location: SIMD2(0, 0))
        let positioned = MapModel(roots: [placedRoot], selected: shifting.id)
        assert(positioned.moveNode(shifting.id, to: stationary.id, at: 0,
                                   location: CGPoint(x: 400, y: 200)))
        assert(positioned.roots[0].children[0].children[0].location == SIMD2(400, 200))
        assert(positioned.roots[0].children[0].children[0].children[0].location == SIMD2(420, 220))
        assert(positioned.undo() && positioned.roots == [placedRoot], "Undo restores original source locations")
        assert(positioned.redo() && positioned.roots[0].children[0].children[0].location == SIMD2(400, 200))
        assert(try! JSONDecoder().decode([MapNode].self, from: JSONEncoder().encode(positioned.roots)) == positioned.roots)
        let rootID = UUID()
        let model = MapModel(roots: [MapNode(id: rootID, title: "Root", children: [], folded: false)], selected: rootID)

        model.addChild()
        let childID = model.selected
        assert(model.roots.count == 1)
        assert(model.roots[0].children.map(\.id) == [childID])

        model.addSibling()
        let siblingID = model.selected
        assert(siblingID != childID)
        assert(model.roots[0].children.map(\.id) == [childID, siblingID])

        model.rename("Renamed")
        assert(model.roots[0].children[1].title == "Renamed")
        assert(model.selected == siblingID)

        model.selected = rootID
        assert(model.toggleFold())
        assert(model.roots[0].folded)
        model.selected = siblingID

        model.remove()
        assert(model.roots[0].children.map(\.id) == [childID])
        assert(model.selected == rootID)

        model.undo()
        assert(model.roots[0].children.map(\.id) == [childID, siblingID])
        assert(model.roots[0].folded)
        assert(model.selected == siblingID)

        model.undo()
        assert(!model.roots[0].folded)
        assert(model.selected == rootID)

        model.undo()
        assert(model.roots[0].children[1].title != "Renamed")
        assert(model.selected == siblingID)

        model.redo()
        assert(model.roots[0].children[1].title == "Renamed")
        model.redo()
        assert(model.roots[0].folded)
        model.redo()
        assert(model.roots[0].children.map(\.id) == [childID])
        assert(model.selected == rootID)

        model.remove() // The sole root cannot be deleted.
        assert(model.roots.map(\.id) == [rootID])
        assert(model.roots[0].children.map(\.id) == [childID])
        assert(model.selected == rootID)

        model.undo() // Rejected removal must not add an undo entry.
        assert(model.roots[0].children.map(\.id) == [childID, siblingID])
        assert(model.selected == siblingID)

        let foldedRootID = UUID()
        let folded = MapModel(roots: [MapNode(id: foldedRootID, title: "Folded", children: [], folded: true)], selected: foldedRootID)
        folded.addChild()
        let visibleChildID = folded.selected
        assert(!folded.roots[0].folded)
        assert(folded.roots[0].children.map(\.id) == [visibleChildID])
        folded.undo()
        assert(folded.roots[0].folded)
        assert(folded.roots[0].children.isEmpty)
        assert(folded.selected == foldedRootID)
        folded.redo()
        assert(!folded.roots[0].folded)
        assert(folded.roots[0].children.map(\.id) == [visibleChildID])
        assert(folded.selected == visibleChildID)

        let treeRootID = UUID()
        let tree = MapModel(roots: [MapNode(id: treeRootID, title: "Tree", children: [], folded: false)], selected: treeRootID)
        tree.addChild()
        let branchID = tree.selected
        tree.rename("Branch")
        tree.addChild()
        let innerID = tree.selected
        tree.rename("Inner")
        tree.addChild()
        let leafID = tree.selected
        tree.rename("First")
        tree.addSibling()
        let deepSiblingID = tree.selected
        tree.rename("Second")
        assert(tree.roots[0].children.map(\.title) == ["Branch"])
        assert(tree.roots[0].children[0].children.map(\.title) == ["Inner"])
        assert(tree.roots[0].children[0].children[0].children.map(\.id) == [leafID, deepSiblingID])
        assert(tree.roots[0].children[0].children[0].children.map(\.title) == ["First", "Second"])
        assert(tree.selected == deepSiblingID)
        tree.undo() // Undo the deep sibling's rename.
        tree.undo() // Undo insertion at depth three.
        assert(tree.roots[0].children[0].children[0].children.map(\.id) == [leafID])
        assert(tree.selected == leafID)
        tree.redo()
        tree.redo()
        assert(tree.roots[0].children[0].children[0].children.map(\.id) == [leafID, deepSiblingID])
        assert(tree.roots[0].children[0].children[0].children.map(\.title) == ["First", "Second"])
        assert(tree.selected == deepSiblingID)

        tree.selected = branchID
        tree.remove() // Delete the whole three-level subtree.
        assert(tree.roots[0].children.isEmpty)
        assert(tree.selected == treeRootID)
        tree.undo()
        assert(tree.roots[0].children.map(\.id) == [branchID])
        assert(tree.roots[0].children.map(\.title) == ["Branch"])
        assert(tree.roots[0].children[0].children.map(\.id) == [innerID])
        assert(tree.roots[0].children[0].children.map(\.title) == ["Inner"])
        assert(tree.roots[0].children[0].children[0].children.map(\.id) == [leafID, deepSiblingID])
        assert(tree.roots[0].children[0].children[0].children.map(\.title) == ["First", "Second"])
        assert(tree.selected == branchID)
        tree.redo()
        assert(tree.roots[0].children.isEmpty)
        assert(tree.selected == treeRootID)
        let blank = MapModel(roots: [], selected: UUID())
        blank.addChild() // An empty imported map must be editable.
        assert(blank.roots.count == 1 && blank.roots[0].id == blank.selected)
        blank.rename("First idea")
        assert(blank.roots[0].title == "First idea")
        blank.undo()
        blank.undo()
        assert(blank.roots.isEmpty)
        blank.redo()
        assert(blank.roots.count == 1 && blank.roots[0].id == blank.selected)
        let movedRoot = UUID()
        let moved = MapModel(roots: [MapNode(id: movedRoot, title: "Root", children: [
            MapNode(id: UUID(), title: "First", children: [], folded: false),
            MapNode(id: UUID(), title: "Middle", children: [MapNode(id: UUID(), title: "Descendant", children: [], folded: false)], folded: false),
            MapNode(id: UUID(), title: "Last", children: [], folded: false)
        ], folded: false)], selected: movedRoot)
        moved.selected = moved.roots[0].children[1].id
        let movedID = moved.selected
        assert(moved.moveSibling(by: -1))
        assert(moved.roots[0].children.map(\.title) == ["Middle", "First", "Last"])
        assert(moved.roots[0].children[0].children[0].title == "Descendant")
        assert(moved.selected == movedID)
        assert(!moved.moveSibling(by: -1)) // A boundary move creates no undo entry.
        assert(!moved.moveSibling(by: Int.min)) // Invalid steps must never trap.
        moved.undo()
        assert(moved.roots[0].children.map(\.title) == ["First", "Middle", "Last"])
        moved.redo()
        moved.moveSibling(by: 1)
        assert(moved.roots[0].children.map(\.title) == ["First", "Middle", "Last"])
        let a = UUID(), b = UUID(), c = UUID()
        let previewModel = MapModel(roots: [MapNode(id: a, title: "Root", children: [
            MapNode(id: b, title: "Source", children: [], folded: false),
            MapNode(id: c, title: "Target", children: [], folded: false)
        ], folded: false)], selected: b)
        let unchanged = previewModel.roots
        assert(previewModel.canMoveNode(b, to: c, at: 0))
        assert(!previewModel.canMoveNode(a, to: c, at: 0))
        assert(!previewModel.canMoveNode(b, to: b, at: 0))
        assert(!previewModel.canMoveNode(b, to: a, at: 1)) // Same location.
        assert(previewModel.roots == unchanged && previewModel.selected == b)
        assert(!previewModel.undo(), "A validity query must not add undo history")
        assert(previewModel.roots == unchanged)
        previewModel.rename("Edited")
        assert(previewModel.undo())
        assert(previewModel.canMoveNode(b, to: c, at: 0))
        assert(previewModel.redo(), "A validity query must not clear redo history")
        assert(previewModel.roots[0].children[0].title == "Edited")
        let sourceID = UUID(), nestedID = UUID(), destinationID = UUID()
        let dragged = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: sourceID, title: "Source", children: [MapNode(id: nestedID, title: "Nested", children: [], folded: false)], folded: false),
            MapNode(id: destinationID, title: "Destination", children: [], folded: true)
        ], folded: false)], selected: sourceID)
        assert(!dragged.moveNode(sourceID, to: nestedID, at: 0), "Cannot move a parent into its descendant")
        assert(!dragged.moveNode(sourceID, to: sourceID, at: 0))
        assert(!dragged.moveNode(sourceID, to: destinationID, at: -1))
        assert(dragged.moveNode(sourceID, to: destinationID, at: 0))
        assert(dragged.roots[0].children.map(\.id) == [destinationID])
        assert(dragged.roots[0].children[0].children.map(\.id) == [sourceID])
        assert(dragged.roots[0].children[0].children[0].children.map(\.id) == [nestedID])
        assert(!dragged.roots[0].children[0].folded && dragged.selected == sourceID)
        dragged.undo()
        assert(dragged.roots[0].children.map(\.id) == [sourceID, destinationID])
        assert(dragged.roots[0].children[1].folded)
        dragged.redo()
        assert(dragged.roots[0].children[0].children.map(\.id) == [sourceID])
        let ordered = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "A", children: [], folded: false),
            MapNode(id: UUID(), title: "B", children: [], folded: false),
            MapNode(id: UUID(), title: "C", children: [], folded: false)
        ], folded: false)], selected: UUID())
        let parentID = ordered.roots[0].id
        assert(ordered.moveNode(ordered.roots[0].children[0].id, to: parentID, at: 3))
        assert(ordered.roots[0].children.map(\.title) == ["B", "C", "A"])
        assert(!ordered.moveNode(ordered.roots[0].children[2].id, to: parentID, at: 3))
        ordered.undo()
        assert(ordered.roots[0].children.map(\.title) == ["A", "B", "C"])
        assert(!ordered.moveNode(ordered.roots[0].children[0].id, to: parentID, at: 0))
        assert(!ordered.moveNode(ordered.roots[0].children[0].id, to: parentID, at: Int.max))
        assert(ordered.redo(), "Rejected moves must preserve redo history")
        assert(ordered.roots[0].children.map(\.title) == ["B", "C", "A"])
        let insertRoot = UUID(), wrappedID = UUID(), neighborID = UUID()
        let insertion = MapModel(roots: [MapNode(id: insertRoot, title: "Main", children: [
            MapNode(id: wrappedID, title: "Existing", children: [MapNode(id: UUID(), title: "Leaf", children: [], folded: false)], folded: false),
            MapNode(id: neighborID, title: "Neighbor", children: [], folded: false)
        ], folded: false)], selected: wrappedID)
        insertion.addSibling(before: true)
        let precedingID = insertion.selected
        assert(insertion.roots[0].children.map(\.id) == [precedingID, wrappedID, neighborID])
        insertion.undo()
        assert(insertion.roots[0].children.map(\.id) == [wrappedID, neighborID])
        insertion.selected = wrappedID
        insertion.addParent()
        let newParentID = insertion.selected
        assert(insertion.roots[0].children.map(\.id) == [newParentID, neighborID])
        assert(insertion.roots[0].children[0].children.map(\.id) == [wrappedID])
        assert(insertion.roots[0].children[0].children[0].children.map(\.title) == ["Leaf"])
        insertion.undo()
        assert(insertion.roots[0].children.map(\.id) == [wrappedID, neighborID])
        insertion.selected = insertRoot
        insertion.addMainNode()
        assert(insertion.roots.count == 2 && insertion.roots[1].id == insertion.selected)
        insertion.undo()
        assert(insertion.roots.map(\.id) == [insertRoot])
        let detachedRoot = UUID(), detachedChild = UUID(), detachedLeaf = UUID()
        let detachable = MapModel(roots: [MapNode(id: detachedRoot, title: "Root", children: [
            MapNode(id: detachedChild, title: "Branch", children: [
                MapNode(id: detachedLeaf, title: "Leaf", children: [], folded: false)
            ], folded: false)
        ], folded: false)], selected: detachedChild)
        assert(detachable.detachSelected())
        assert(detachable.roots.map(\.id) == [detachedRoot, detachedChild])
        assert(detachable.roots[0].children.isEmpty)
        assert(detachable.roots[1].children.map(\.id) == [detachedLeaf])
        assert(detachable.selected == detachedChild)
        assert(!detachable.detachSelected()) // Already a root; no extra undo entry.
        detachable.undo()
        assert(detachable.roots.map(\.id) == [detachedRoot])
        assert(detachable.roots[0].children.map(\.id) == [detachedChild])

        let loneLeafID = UUID()
        let leaf = MapModel(roots: [MapNode(id: loneLeafID, title: "Leaf", children: [], folded: false)], selected: loneLeafID)
        leaf.rename("Edited")
        assert(leaf.undo())
        assert(!leaf.toggleFold()) // A leaf cannot fold or discard its redo history.
        assert(!leaf.roots[0].folded)
        assert(leaf.redo())
        assert(leaf.roots[0].title == "Edited")
        assert(!leaf.redo())
        assert(leaf.undo())
        assert(!leaf.undo()) // Rejected fold must not create an undo entry.
        assert(leaf.roots[0].title == "Leaf")
        assert(!leaf.toggleFold() && !leaf.roots[0].folded)

        let groupRoot = UUID(), left = UUID(), nested = UUID(), right = UUID(), target = UUID()
        let groupTree = MapNode(id: groupRoot, title: "Root", children: [
            MapNode(id: left, title: "Left", children: [MapNode(id: nested, title: "Nested", children: [], folded: false,
                location: SIMD2(120, 90))], folded: false, location: SIMD2(100, 70)),
            MapNode(id: right, title: "Right", children: [], folded: false, location: SIMD2(180, 70)),
            MapNode(id: target, title: "Target", children: [], folded: false, location: SIMD2(320, 70))
        ], folded: false)
        let group = MapModel(roots: [groupTree], selected: left)
        assert(group.selectedIDs == [left])
        assert(group.toggleSelection(right) && group.selectedIDs == [left, right] && group.selected == right)
        assert(group.setWidth(240))
        assert(group.roots[0].children[0].width == 240 && group.roots[0].children[1].width == 240)
        assert(group.undo() && group.roots == [groupTree] && group.selectedIDs == [left, right])
        assert(group.redo() && group.roots[0].children[1].width == 240)
        assert(group.setFont(family: "Helvetica", size: 22))
        assert(group.roots[0].children[0].fontSize == 22 && group.roots[0].children[1].fontSize == 22)
        assert(group.setAlignment("center") && group.setBranchStroke(width: 3, color: "#112233FF", style: "dashed"))
        assert(group.roots[0].children[0].strokeStyle == "dashed")
        assert(group.resizeSelected(by: 20, visibleWidths: [left: 240, right: 260]))
        assert(group.roots[0].children[0].width == 260 && group.roots[0].children[1].width == 280)
        assert(group.roots[0].children[0].location == SIMD2(110, 70) &&
               group.roots[0].children[1].location == SIMD2(190, 70))
        assert(group.undo() && group.roots[0].children[0].width == 240)
        assert(group.redo() && group.roots[0].children[1].width == 280)
        assert(group.roots[0].children[0].textAlignment == "center" && group.roots[0].children[1].branchStrokeWidth == 3)
        assert(group.setFont(size: 26) && group.roots[0].children.allSatisfy {
            $0.id == target || ($0.fontSize == 26 && $0.fontFamily == "Helvetica")
        })
        assert(group.setBranchStroke(color: "#aabbccff") &&
               group.roots[0].children[0].branchStrokeColor == "#AABBCCFF" &&
               group.roots[0].children[1].strokeStyle == "dashed")
        assert(!group.setBranchStroke(width: .nan, color: "#112233FF", style: "solid") &&
               !group.setBranchStroke(width: 2, color: "bad", style: "solid") &&
               !group.setBranchStroke(width: 2, color: "#112233FF", style: "dotted") &&
               !group.setAlignment("diagonal"))
        let beforeInvalid = group.roots
        assert(!group.moveSelectedNodes(to: nested, at: 0))
        assert(!group.moveSelectedNodes(to: groupRoot, at: 0), "Identity group move cannot unfold or add history")
        assert(!group.moveSelectedNodes(to: target, at: 0, locations: [left: CGPoint(x: CGFloat.nan, y: 0),
                                                                      right: CGPoint(x: 480, y: 200)]))
        assert(group.roots == beforeInvalid)
        assert(group.moveSelectedNodes(to: target, at: 0, locations: [left: CGPoint(x: 400, y: 200),
                                                                    right: CGPoint(x: 480, y: 200)]))
        assert(group.roots[0].children.map(\.id) == [target])
        assert(group.roots[0].children[0].children.map(\.id) == [left, right])
        assert(group.roots[0].children[0].children[0].children[0].location == SIMD2(430, 220),
               "Resized descendant keeps its 20pt branch gap when the entire group is subsequently reparented")
        assert(group.undo() && group.roots == beforeInvalid && group.selectedIDs == [left, right])
        assert(group.redo() && group.roots[0].children[0].children.map(\.id) == [left, right])
        group.selected = left
        assert(group.selectedIDs == [left], "Legacy direct primary selection resets to single selection")
        assert(group.selectRange(to: right) && group.selectedIDs == [left, right])
        assert(group.toggleSelection(nested) && group.selectedIDs.contains(nested))
        assert(!group.moveSelectedNodes(to: nested, at: 0))
        assert(try! JSONDecoder().decode([MapNode].self, from: JSONEncoder().encode(group.roots)) == group.roots)
        let ranged = MapModel(roots: [groupTree], selected: left)
        assert(ranged.selectRange(to: right) && ranged.selectRange(to: target))
        assert(ranged.selectedIDs == [left, right, target], "Repeated Shift extends from original anchor")
        let ancestorGroup = MapModel(roots: [groupTree], selected: left)
        assert(ancestorGroup.toggleSelection(nested))
        assert(ancestorGroup.moveSelectedNodes(to: target, at: 0))
        assert(ancestorGroup.roots[0].children[1].children.map(\.id) == [left])
        assert(ancestorGroup.roots[0].children[1].children[0].children.map(\.id) == [nested])
        assert(ancestorGroup.undo() && ancestorGroup.roots == [groupTree])
        let edge = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "Near edge", children: [], folded: false, location: SIMD2(999_990, 0)),
            MapNode(id: UUID(), title: "Safe", children: [], folded: false, location: SIMD2(100, 0))
        ], folded: false)], selected: UUID())
        let edgeIDs = edge.roots[0].children.map(\.id)
        edge.selected = edgeIDs[0]
        assert(edge.toggleSelection(edgeIDs[1]))
        let edgeBefore = edge.roots
        assert(!edge.setWidth(1000, anchoredFrom: 60))
        assert(!edge.resizeSelected(by: 940, visibleWidths: [edgeIDs[0]: 60, edgeIDs[1]: 60]))
        assert(edge.roots == edgeBefore && !edge.undo(), "One invalid center rejects the whole batch")

        let initial = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [], folded: false)], selected: UUID())
        initial.selected = initial.roots[0].id
        initial.addChild()
        let newID = initial.selected
        initial.rename("First title", initialWidth: 210)
        assert(initial.roots[0].children[0].width == 210 && initial.roots[0].children[0].title == "First title")
        assert(initial.undo() && initial.roots[0].children[0].width == nil)
        initial.rename("Alternate first", initialWidth: 180)
        assert(initial.roots[0].children[0].width == 180, "Undo restores the first-title width marker")
        assert(initial.undo() && initial.redo() && initial.roots[0].children[0].width == 180)
        initial.rename("Later", initialWidth: 350)
        assert(initial.roots[0].children[0].width == 180 && initial.selected == newID)
        let imported = MapModel(roots: [MapNode(id: UUID(), title: "", children: [], folded: false)], selected: UUID())
        imported.selected = imported.roots[0].id
        imported.rename("Imported", initialWidth: 200)
        assert(imported.roots[0].width == nil, "Legacy blank nodes keep content-sized width")
        let noteRoot = UUID(), noteSibling = UUID()
        let notes = MapModel(roots: [noteRoot, noteSibling].map {
            MapNode(id: $0, title: "Node", children: [], folded: false)
        }, selected: noteRoot)
        assert(!notes.setNote("") && !notes.undo(), "Empty note must not create Undo")
        assert(!notes.setNote(String(repeating: "é", count: 32_769)))
        assert(!notes.undo(), "Oversized UTF-8 note must not create Undo")
        assert(notes.setNote("Example") && notes.roots[0].note == "Example" && notes.roots[1].note == nil)
        assert(!notes.setNote("Example") && notes.undo() && notes.roots[0].note == nil)
        assert(!notes.undo() && notes.redo() && notes.roots[0].note == "Example")
        assert(notes.selectNodes([noteRoot, noteSibling]) && !notes.setNote("Not for a group"))
        notes.selectOnly(noteRoot)
        assert(notes.setRootShape("rounded") && notes.setRootFillColor("#aabbccff"))
        assert(notes.roots[0].rootShape == "rounded" && notes.roots[0].rootFillColor == "#AABBCCFF")
        assert(!notes.setRootShape("oval") && !notes.setRootFillColor("red"))
        assert(notes.setTheme("tropical") && notes.theme == "tropical")
        assert(!notes.setTheme("tropical") && !notes.setTheme("unknown"))
        assert(notes.undo() && notes.theme == nil && notes.redo() && notes.theme == "tropical")
        assert(notes.setCanvasColor("#102030ff") && notes.canvasColor == "#102030FF")
        assert(!notes.setCanvasColor("#10203") && notes.undo() && notes.canvasColor == nil)
        notes.selectOnly(noteSibling)
        assert(notes.setNote("Sibling") && notes.roots[0].note == "Example" && notes.roots[1].note == "Sibling")
        let nestedNotes = MapModel(roots: [MapNode(id: noteRoot, title: "Root", children: [
            MapNode(id: noteSibling, title: "Child", children: [], folded: false)
        ], folded: false)], selected: noteSibling)
        assert(!nestedNotes.setRootShape("rectangle") && !nestedNotes.setRootFillColor("#112233FF") && !nestedNotes.undo())
        var nearLimit = MapNode(id: UUID(), title: "", children: [], folded: false)
        let bareSize = try! JSONEncoder().encode([nearLimit]).count
        nearLimit.title = String(repeating: "x", count: MapModel.maxSavedJSONBytes - bareSize - 20)
        let bounded = MapModel(roots: [nearLimit], selected: nearLimit.id)
        assert(!bounded.setNote(String(repeating: "y", count: 128)) && bounded.roots == [nearLimit])
        assert(!bounded.setTheme("rainbow") && !bounded.setCanvasColor("#102030FF") && !bounded.undo(),
               "Inspector changes must not create a document exceeding 32 MiB")
        print("model tests passed")
    }
}
