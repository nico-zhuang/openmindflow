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
        let grandchild = UUID(), sibling = UUID()
        let tree = MapModel(roots: [MapNode(id: root, title: "Root", children: [
            MapNode(id: child, title: "Child", children: [
                MapNode(id: grandchild, title: "Grandchild 🧭", children: [], folded: false)
            ], folded: false),
            MapNode(id: sibling, title: "Sibling", children: [], folded: false)
        ], folded: false)], selected: root)
        let mapCanvas = MapCanvas(model: tree)
        let outline = MapOutlineView(canvas: mapCanvas)
        mapCanvas.onSelectionChange = { outline.syncSelection() }
        var outlineChanges = 0
        mapCanvas.onChange = { outlineChanges += 1; outline.reloadMap() }
        assert(outline.outlineView.numberOfRows == 4)
        assert(outline.outlineView.selectedRow == 0)
        mapCanvas.selectAndEdit(root)
        mapCanvas.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "Committed before outline selection"
        outline.outlineView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        assert(tree.roots[0].title == "Committed before outline selection")
        assert(tree.selected == child && outline.outlineView.selectedRow == 1 && outlineChanges == 1)
        assert(outline.outlineView.target === outline && outline.outlineView.doubleAction != nil,
               "A native outline double-click must reopen the selected node editor")
        _ = outline.perform(outline.outlineView.doubleAction!, with: outline.outlineView)
        assert(tree.selected == child && mapCanvas.subviews.contains { $0 is NSTextField },
               "Outline editing must use the same canvas model and native field")
        mapCanvas.commitEditing()
        let grandchildLabel = outline.outlineView.view(atColumn: 0, row: 2, makeIfNecessary: true) as? NSTextField
        assert(grandchildLabel?.toolTip == "Grandchild 🧭")
        assert(outline.outlineView.accessibilityLabel() == "Map outline")
        outline.reloadMap()
        assert(tree.selected == child && outline.outlineView.numberOfRows == 4 && outlineChanges == 1)
        mapCanvas.toggleFold()
        assert(tree.roots[0].children[0].folded && outline.outlineView.numberOfRows == 3)
        mapCanvas.undo()
        assert(!tree.roots[0].children[0].folded && outline.outlineView.numberOfRows == 4)
        let childItem = outline.outlineView.item(atRow: 1)!
        outline.outlineView.collapseItem(childItem) // Native disclosure action, not a model call.
        if outline.outlineView.item(atRow: 1)! as AnyObject !== childItem as AnyObject {
            fputs("Native disclosure replaced its own Row before returning; AppKit may use freed item\n", stderr)
            exit(1) // Exit normally: a failing diagnostic must not trigger another macOS crash dialog.
        }
        assert(tree.roots[0].children[0].folded)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        assert(outline.outlineView.numberOfRows == 3)
        let foldedChild = outline.outlineView.item(atRow: 1)!
        outline.outlineView.expandItem(foldedChild)
        if outline.outlineView.item(atRow: 1)! as AnyObject !== foldedChild as AnyObject {
            fputs("Native expansion replaced its own Row before returning\n", stderr)
            exit(1)
        }
        assert(!tree.roots[0].children[0].folded)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        assert(outline.outlineView.numberOfRows == 4)
        mapCanvas.undo()
        assert(tree.roots[0].children[0].folded && outline.outlineView.numberOfRows == 3)
        mapCanvas.undo()
        assert(!tree.roots[0].children[0].folded && outline.outlineView.numberOfRows == 4)
        let beforeLeaf = outlineChanges
        outline.outlineView.collapseItem(outline.outlineView.item(atRow: 2)!)
        assert(outlineChanges == beforeLeaf && outline.outlineView.numberOfRows == 4)

        let many = MapNode(id: UUID(), title: "Thirty", children: (0..<29).map { index in
            MapNode(id: UUID(), title: "Node \(index)", children: [], folded: false)
        }, folded: false)
        let manyCanvas = MapCanvas(model: MapModel(roots: [many], selected: many.id))
        let manyOutline = MapOutlineView(canvas: manyCanvas)
        assert(manyOutline.outlineView.numberOfRows == 30)
        manyOutline.reloadMap()
        assert(manyOutline.outlineView.numberOfRows == 30)

        let delegate = AppDelegate()
        let workbench = delegate.makeWorkbench(canvas: manyCanvas)
        assert(workbench.splitViewItems.count == 2)
        let sidebar = workbench.splitViewItems[0]
        assert(sidebar.canCollapse && sidebar.minimumThickness == 180 && sidebar.maximumThickness == 320)
        assert(sidebar.viewController.view is MapOutlineView)
        assert(workbench.splitViewItems[1].viewController.view === manyCanvas,
               "The outline and workspace must share the original canvas")
        let unchanged = manyCanvas.model.roots
        workbench.toggleSidebar(nil)
        assert(manyCanvas.model.roots == unchanged, "Toggling sidebar cannot mutate the map")
        print("outline selection, fold/undo, 30-node and split workbench tests passed (offscreen only)")
    }
}
