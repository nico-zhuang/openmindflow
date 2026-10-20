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
        print("model tests passed")
    }
}
