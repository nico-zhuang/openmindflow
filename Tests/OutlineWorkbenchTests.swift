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
        for (key, code) in [("\r", UInt16(36)), ("\u{3}", UInt16(76))] {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: code) else {
                fputs("Could not create local outline Return/Enter event\n", stderr); exit(1)
            }
            outline.outlineView.keyDown(with: event) // Direct local event; never posted to the desktop.
            guard tree.selected == child,
                  mapCanvas.subviews.compactMap({ $0 as? NSTextField }).first?.stringValue == "Child" else {
                fputs("Outline Return/Enter must edit the selected node on the shared canvas\n", stderr)
                exit(1) // Expected RED must not create a macOS assertion/crash dialog.
            }
            mapCanvas.commitEditing()
        }
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

        let rightA = MapNode(id: UUID(), title: "A", children: [], folded: false)
        let rightB = MapNode(id: UUID(), title: "B", children: [], folded: false)
        let rightRoot = MapNode(id: UUID(), title: "Root", children: [rightA, rightB], folded: false)
        let rightModel = MapModel(roots: [rightRoot], selected: rightA.id)
        let rightCanvas = MapCanvas(model: rightModel)
        let rightOutline = MapOutlineView(canvas: rightCanvas)
        let rightWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
                                   styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        rightWindow.contentView = rightOutline // Attached but never shown or activated.
        rightWindow.contentView?.layoutSubtreeIfNeeded()
        let rowBox = rightOutline.outlineView.rect(ofRow: 2)
        let rowPoint = rightOutline.outlineView.convert(CGPoint(x: rowBox.midX, y: rowBox.midY), to: nil)
        let rightEvent = NSEvent.mouseEvent(with: .rightMouseDown, location: rowPoint,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        guard let context = rightOutline.outlineView.menu(for: rightEvent),
              rightModel.selected == rightB.id,
              context.item(withTitle: "Edit Title")?.target as AnyObject? === rightCanvas else {
            fputs("Right-clicking an outline row must select it and offer its canvas node commands\n", stderr)
            exit(1)
        }
        rightWindow.orderOut(nil)

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
        assert(workbench.splitViewItems.count == 3 &&
               workbench.splitViewItems[2].viewController.view is StyleInspector,
               "Workbench must expose a native right-side Style inspector beside outline and canvas")
        let sidebar = workbench.splitViewItems[0]
        assert(sidebar.canCollapse && sidebar.minimumThickness == 180 && sidebar.maximumThickness == 320)
        assert(sidebar.viewController.view is MapOutlineView)
        assert(workbench.splitViewItems[1].viewController.view === manyCanvas,
               "The outline and workspace must share the original canvas")
        let sideWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        sideWindow.contentViewController = workbench // Never shown or activated.
        sideWindow.contentView?.layoutSubtreeIfNeeded()
        assert(sideWindow.contentView!.bounds.width >= 1000 && manyCanvas.bounds.width >= 400 &&
               manyCanvas.bounds.height >= 400,
               "Attaching the three-column controller must not shrink the window and canvas to a zero-width 26pt strip")
        let attachedOutline = sidebar.viewController.view as! MapOutlineView
        assert(sideWindow.makeFirstResponder(attachedOutline.outlineView))
        delegate.installMenu()
        let item = NSApp.mainMenu!.item(withTitle: "View")!.submenu!.item(withTitle: "Show/Hide Outline")!
        let unchanged = manyCanvas.model.roots
        let expandedCanvasWidth = manyCanvas.bounds.width
        let hideSent = NSApp.sendAction(item.action!, to: item.target, from: item)
        sideWindow.contentView?.layoutSubtreeIfNeeded()
        guard hideSent, sidebar.isCollapsed, sideWindow.firstResponder === manyCanvas,
              manyCanvas.bounds.width > expandedCanvasWidth + 100 else {
            fputs("Hiding outline must collapse and focus canvas (sent=\(hideSent), collapsed=\(sidebar.isCollapsed), responder=\(String(describing: sideWindow.firstResponder)))\n", stderr)
            exit(1)
        }
        guard NSApp.sendAction(item.action!, to: item.target, from: item), !sidebar.isCollapsed,
              manyCanvas.model.roots == unchanged else {
            fputs("Showing outline must restore its sidebar without changing the map\n", stderr)
            exit(1)
        }
        sideWindow.contentView?.layoutSubtreeIfNeeded()
        let stableFrame = sideWindow.frame
        for _ in 0..<6 {
            assert(NSApp.sendAction(item.action!, to: item.target, from: item))
            sideWindow.contentView?.layoutSubtreeIfNeeded()
            guard sideWindow.frame == stableFrame else {
                fputs("Outline shifted window: before=\(stableFrame), after=\(sideWindow.frame), collapsed=\(sidebar.isCollapsed)\n", stderr)
                exit(1)
            }
        }
        assert(!sidebar.isCollapsed)
        let toolbar = delegate.makeToolbar()
        let styleID = NSToolbarItem.Identifier("style")
        assert(delegate.toolbarDefaultItemIdentifiers(toolbar).contains(styleID),
               "Toolbar must expose a native Show/Hide Style inspector switch")
        guard let styleButton = delegate.toolbar(toolbar, itemForItemIdentifier: styleID, willBeInsertedIntoToolbar: true),
              let action = styleButton.action else { fatalError("Style toolbar switch missing") }
        let inspectorItem = workbench.splitViewItems[2]
        assert(NSApp.sendAction(action, to: styleButton.target, from: styleButton) && inspectorItem.isCollapsed)
        assert(sideWindow.frame == stableFrame, "Right inspector collapse cannot resize or shift the window")
        assert(NSApp.sendAction(action, to: styleButton.target, from: styleButton) && !inspectorItem.isCollapsed)
        assert(sideWindow.frame == stableFrame)
        sideWindow.orderOut(nil)

        let deepest = UUID()
        let narrowRoot = MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "Child", children: [
                MapNode(id: UUID(), title: "Grandchild", children: [
                    MapNode(id: deepest, title: "Deepest", children: [], folded: false)
                ], folded: false)
            ], folded: false)
        ], folded: false)
        let narrowCanvas = MapCanvas(model: MapModel(roots: [narrowRoot], selected: deepest))
        narrowCanvas.frame = CGRect(x: 0, y: 0, width: 1100, height: 700)
        narrowCanvas.selectAndEdit(deepest)
        let narrowEditor = narrowCanvas.subviews.compactMap { $0 as? NSTextField }.first!
        narrowCanvas.frame.size.width = 400 // Sidebar or window resizing narrows the canvas while editing.
        if !narrowCanvas.bounds.insetBy(dx: 28, dy: 28).contains(narrowEditor.frame) {
            fputs("Inline editor remains outside the narrowed canvas after resize\n", stderr)
            exit(1) // Expected RED must not generate a macOS assertion/crash dialog.
        }
        print("outline selection, fold/undo, 30-node and split workbench tests passed (offscreen only)")
    }
}
