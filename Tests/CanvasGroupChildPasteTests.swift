import AppKit

@main enum CanvasGroupChildPasteTests {
    static func main() {
        _ = NSApplication.shared // Named private pasteboard and detached canvas only.
        let one = MapNode(id: UUID(), title: "One", children: [], folded: false)
        let two = MapNode(id: UUID(), title: "Two", children: [], folded: false)
        let destination = MapNode(id: UUID(), title: "Target", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Main", children: [one, two, destination], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: one.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1300, height: 800)
        let board = NSPasteboard(name: .init("openmindflow-group-child-\(UUID())"))
        defer { board.releaseGlobally() }
        assert(canvas.model.selectNodes([one.id, two.id]))
        assert(canvas.copySelection(to: board))
        assert(canvas.model.selectOnly(destination.id))
        let original = canvas.model.roots
        assert(canvas.paste(from: board), "Selected node must accept multiple copied branches as children")
        guard canvas.model.roots.count == 1,
              canvas.model.roots[0].children.map(\.id).prefix(3) == [one.id, two.id, destination.id],
              canvas.model.roots[0].children.last?.children.map(\.title) == ["One", "Two"] else {
            fatalError("Pasting a copied group into a selected node must not make independent main nodes")
        }
        let children = canvas.model.roots[0].children.last!.children
        assert(canvas.model.selectedIDs == Set(children.map(\.id)) &&
               children.allSatisfy { $0.location == nil })
        canvas.undo()
        assert(canvas.model.roots == original && canvas.model.selectedIDs == [destination.id],
               "One Undo restores old source branches, destination and selection")
        canvas.model.clearSelection()
        assert(canvas.paste(from: board) && canvas.model.roots.count == 3 &&
               canvas.model.roots.dropFirst().map(\.title) == ["One", "Two"],
               "The identical private clipboard makes separate roots only with blank selection")
        print("selected-target group child paste, blank roots, unique IDs and single Undo passed")
    }
}
