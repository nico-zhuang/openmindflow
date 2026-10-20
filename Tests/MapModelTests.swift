import Foundation

@main
enum MapModelTests {
    static func main() {
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

        model.toggleFold()
        assert(model.roots[0].children[1].folded)
        assert(model.selected == siblingID)

        model.remove()
        assert(model.roots[0].children.map(\.id) == [childID])
        assert(model.selected == rootID)

        model.undo()
        assert(model.roots[0].children.map(\.id) == [childID, siblingID])
        assert(model.roots[0].children[1].folded)
        assert(model.selected == siblingID)

        model.undo()
        assert(!model.roots[0].children[1].folded)
        assert(model.selected == siblingID)

        model.undo()
        assert(model.roots[0].children[1].title != "Renamed")
        assert(model.selected == siblingID)

        model.redo()
        assert(model.roots[0].children[1].title == "Renamed")
        model.redo()
        assert(model.roots[0].children[1].folded)
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
        print("model tests passed")
    }
}
