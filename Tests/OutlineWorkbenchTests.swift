import AppKit

@main
enum OutlineWorkbenchTests {
    static func main() {
        _ = NSApplication.shared // Offscreen only; no window or event loop.
        let root = UUID(), child = UUID()
        let model = MapModel(roots: [MapNode(id: root, title: "Root", children: [
            MapNode(id: child, title: "Child", children: [], folded: false)
        ], folded: false)], selected: root)
        let canvas = MapCanvas(model: model)
        var changes = 0
        var selections: [UUID] = []
        canvas.onChange = { changes += 1 }
        canvas.onSelectionChange = { selections.append(model.selected) }
        canvas.selectAndEdit(root)
        let field = canvas.subviews.compactMap { $0 as? NSTextField }.first!
        field.stringValue = "Old title"
        canvas.selectNode(child)
        assert(model.roots[0].title == "Old title", "Commit previous node before selecting new one")
        assert(model.selected == child && changes == 1 && selections == [child])
        assert(canvas.subviews.allSatisfy { !($0 is NSTextField) })
        canvas.selectNode(child)
        canvas.selectNode(UUID()) // Unknown nodes cannot disturb selection/history.
        assert(model.selected == child && changes == 1 && selections == [child])
        canvas.selectAndEdit(root)
        assert(model.selected == root && selections == [child, root])
        assert(canvas.subviews.contains { $0 is NSTextField })
        print("outline canvas selection tests passed (offscreen only)")
    }
}
