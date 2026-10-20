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
        print("model tests passed")
    }
}
