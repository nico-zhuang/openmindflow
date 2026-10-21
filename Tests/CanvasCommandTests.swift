import AppKit

@main
enum CanvasCommandTests {
    static func main() {
        _ = NSApplication.shared // Initialize AppKit without creating or running a window.
        let blank = MapModel(roots: [], selected: UUID())
        let blankCanvas = MapCanvas(model: blank)
        blankCanvas.addSibling() // Return command on a newly opened empty document.
        assert(blank.roots.count == 1 && blank.roots[0].id == blank.selected)
        let blankField = blankCanvas.subviews.compactMap { $0 as? NSTextField }.first
        assert(blankField != nil, "New root should enter text editing")
        blankField!.stringValue = "First thought"
        blankCanvas.commitEditing()
        assert(blank.roots[0].title == "First thought")
        var blankChanges = 0
        blankCanvas.onChange = { blankChanges += 1 }
        let delete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{7f}",
            charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
        blankCanvas.keyDown(with: delete)
        assert(blankChanges == 0, "Deleting the only root must not mark the map dirty")
        blankCanvas.addMainNode()
        let afterInsert = blankChanges
        blankCanvas.keyDown(with: delete)
        assert(blankChanges == afterInsert + 1 && blank.roots.count == 1)
        blankCanvas.keyDown(with: delete)
        assert(blankChanges == afterInsert + 1, "Second Delete is a no-op")
        let rootID = UUID(), childID = UUID()
        let model = MapModel(roots: [MapNode(id: rootID, title: "Root", children: [
            MapNode(id: childID, title: "Existing", children: [], folded: false)
        ], folded: false)], selected: childID)
        let canvas = MapCanvas(model: model)
        let control = NSTextField()
        let text = NSTextView()
        canvas.selectAndEdit(childID)
        let field = canvas.subviews.compactMap { $0 as? NSTextField }.first!
        field.stringValue = "Committed child"
        assert(canvas.control(control, textView: text,
            doCommandBy: NSSelectorFromString("insertTabIgnoringFieldEditor:")))
        let parentID = model.selected
        assert(parentID != childID && model.roots[0].children[0].id == parentID)
        assert(model.roots[0].children[0].children.map(\.id) == [childID])
        assert(model.roots[0].children[0].children[0].title == "Committed child")
        canvas.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "Committed parent"
        assert(canvas.control(control, textView: text,
            doCommandBy: NSSelectorFromString("insertNewlineIgnoringFieldEditor:")))
        assert(model.roots[0].children.map(\.id) == [model.selected, parentID])
        assert(model.roots[0].children[1].title == "Committed parent")
        assert(!canvas.control(control, textView: text,
            doCommandBy: NSSelectorFromString("unrecognizedCommand:")))
        let appDelegate = AppDelegate()
        let workbench = appDelegate.makeWorkbench(canvas: canvas)
        appDelegate.installMenu()
        assert(NSApp.mainMenu!.items.map(\.title) == ["MindMap", "File", "Edit", "View", "Node"])
        let viewMenu = NSApp.mainMenu!.items.compactMap(\.submenu).first { $0.title == "View" }!
        let outlineToggle = viewMenu.item(withTitle: "Show/Hide Outline")!
        assert(viewMenu.items.count == 1 && outlineToggle.keyEquivalent == "s")
        assert(outlineToggle.keyEquivalentModifierMask == [.option, .command])
        assert(outlineToggle.action.map(NSStringFromSelector) == "toggleSidebar:")
        assert(outlineToggle.target as AnyObject? === workbench)
        let fileMenu = NSApp.mainMenu!.items.compactMap(\.submenu).first { $0.title == "File" }!
        assert(fileMenu.item(withTitle: "Open MindNode (Read-only)…")?.keyEquivalent == "o")
        assert(fileMenu.item(withTitle: "Open Own JSON…") != nil)
        let nodeMenu = NSApp.mainMenu!.items.compactMap(\.submenu).first { $0.title == "Node" }!
        let before = nodeMenu.item(withTitle: "New Sibling Before")!
        assert(before.keyEquivalent == "\r" && before.keyEquivalentModifierMask == [.option])
        let parent = nodeMenu.item(withTitle: "New Parent")!
        assert(parent.keyEquivalent == "\t" && parent.keyEquivalentModifierMask == [.option])
        let main = nodeMenu.item(withTitle: "New Main Node")!
        assert(main.keyEquivalent == "\r" && main.keyEquivalentModifierMask == [.shift])
        let toolbar = appDelegate.makeToolbar()
        let identifiers = appDelegate.toolbarDefaultItemIdentifiers(toolbar).filter { $0 != .flexibleSpace }
        assert(identifiers.map(\.rawValue) == ["new-child", "new-sibling", "fold-node", "undo", "redo"])
        for (index, pair) in zip(identifiers,
                                 ["newChild:", "newSibling:", "foldNode:", "undoEdit:", "redoEdit:"]).enumerated() {
            let (identifier, action) = pair
            let item = appDelegate.toolbar(toolbar, itemForItemIdentifier: identifier,
                                           willBeInsertedIntoToolbar: true)!
            assert(item.target as AnyObject? === appDelegate)
            assert(item.action.map(NSStringFromSelector) == action)
            assert(item.label == ["New Child", "New Sibling", "Fold/Unfold", "Undo", "Redo"][index])
            assert(!(item.toolTip ?? "").isEmpty)
        }
        let foldRootID = UUID()
        let folding = MapModel(roots: [MapNode(id: foldRootID, title: "Fold", children: [
            MapNode(id: UUID(), title: "Leaf", children: [], folded: false)
        ], folded: false)], selected: foldRootID)
        let foldingCanvas = MapCanvas(model: folding)
        foldingCanvas.selectAndEdit(foldRootID)
        foldingCanvas.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "Committed fold"
        var foldChanges = 0
        foldingCanvas.onChange = { foldChanges += 1 }
        foldingCanvas.toggleFold()
        assert(folding.roots[0].title == "Committed fold" && folding.roots[0].folded && foldChanges == 2,
               "Folding must first commit active title editing")
        foldingCanvas.undo()
        assert(!folding.roots[0].folded && foldChanges == 3)
        folding.selected = folding.roots[0].children[0].id
        foldingCanvas.toggleFold()
        assert(!folding.roots[0].children[0].folded && foldChanges == 3,
               "Folding a leaf must not change the tree or emit a change")
        let movingID = UUID(), destinationID = UUID(), dragRootID = UUID()
        let dragging = MapModel(roots: [MapNode(id: dragRootID, title: "Root", children: [
            MapNode(id: movingID, title: "Move", children: [], folded: false),
            MapNode(id: destinationID, title: "Destination", children: [], folded: false)
        ], folded: false)], selected: dragRootID)
        let dragCanvas = MapCanvas(model: dragging)
        dragCanvas.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        var changes = 0
        dragCanvas.onChange = { changes += 1 }
        let frames = mapLayout(dragging.roots)
        // NSEvent uses bottom-left window coordinates; this canvas is flipped.
        let start = CGPoint(x: frames[1].frame.midX + 80,
                            y: dragCanvas.bounds.height - frames[1].frame.midY - 90)
        let finish = CGPoint(x: frames[2].frame.midX + 80,
                             y: dragCanvas.bounds.height - frames[2].frame.midY - 90)
        func mouse(_ kind: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let originalTree = dragging.roots
        dragCanvas.mouseDown(with: mouse(.leftMouseDown, start))
        let beforeValidPreview = image(dragCanvas)
        dragCanvas.mouseDragged(with: mouse(.leftMouseDragged, finish))
        assert(image(dragCanvas) != beforeValidPreview,
               "A valid target needs visible feedback before release")
        assert(dragging.roots == originalTree && changes == 0,
               "Preview must not change tree or dirty state")
        dragCanvas.mouseUp(with: mouse(.leftMouseUp, finish))
        assert(dragging.roots[0].children.map(\.id) == [destinationID])
        assert(dragging.roots[0].children[0].children.map(\.id) == [movingID])
        assert(dragging.selected == movingID && changes == 1)
        let droppedTree = dragging.roots
        assert(dragging.undo() && dragging.roots == originalTree)
        assert(dragging.redo() && dragging.roots == droppedTree)
        let siblingIDs = (0..<3).map { _ in UUID() }
        let reordered = MapModel(roots: [MapNode(id: UUID(), title: "Root", children:
            siblingIDs.enumerated().map { MapNode(id: $0.element, title: "\($0.offset)", children: [], folded: false) },
            folded: false)], selected: siblingIDs[2])
        let reorderCanvas = MapCanvas(model: reordered)
        reorderCanvas.frame = dragCanvas.frame
        let rows = mapLayout(reordered.roots)
        let from = CGPoint(x: rows[3].frame.midX + 80,
                           y: reorderCanvas.bounds.height - rows[3].frame.midY - 90)
        let beforePoint = CGPoint(x: rows[2].frame.midX + 80,
                                  y: reorderCanvas.bounds.height - rows[2].frame.minY - 92)
        reorderCanvas.mouseDown(with: mouse(.leftMouseDown, from))
        reorderCanvas.mouseDragged(with: mouse(.leftMouseDragged, beforePoint))
        reorderCanvas.mouseUp(with: mouse(.leftMouseUp, beforePoint))
        assert(reordered.roots[0].children.map(\.id) == [siblingIDs[0], siblingIDs[2], siblingIDs[1]])
        let longChildren = (0..<30).map { MapNode(id: UUID(), title: "Idea \($0)", children: [], folded: false) }
        let longRoot = MapNode(id: UUID(), title: "Root", children: longChildren, folded: false)
        let smallCanvas = MapCanvas(model: MapModel(roots: [longRoot], selected: longRoot.id))
        smallCanvas.frame = CGRect(x: 0, y: 0, width: 420, height: 260)
        smallCanvas.selectAndEdit(longChildren[29].id)
        let distantEditor = smallCanvas.subviews.compactMap { $0 as? NSTextField }.first!
        assert(distantEditor.frame.maxY <= smallCanvas.bounds.maxY - 24,
               "Editing a distant node must reveal its field inside the canvas")
        func localWheel(_ amount: Int32, command: Bool = false) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                             wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0)!
            if command { cg.flags = .maskCommand }
            return NSEvent(cgEvent: cg)!
        }
        let firstSize = distantEditor.font!.pointSize
        smallCanvas.scrollWheel(with: localWheel(8, command: true)) // Local NSEvent only, never posted.
        assert(distantEditor.font!.pointSize != firstSize,
               "Zooming during editing must scale the text field font with its node")
        let firstPosition = distantEditor.frame.origin
        smallCanvas.scrollWheel(with: localWheel(30))
        assert(distantEditor.frame.origin != firstPosition,
               "Panning during editing must keep the text field attached to its node")
        let visualRoot = MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "Source", children: [], folded: false),
            MapNode(id: UUID(), title: "Destination", children: [], folded: false)
        ], folded: false)
        let visualModel = MapModel(roots: [visualRoot], selected: visualRoot.id)
        let visualCanvas = MapCanvas(model: visualModel)
        visualCanvas.frame = dragCanvas.frame
        var visualChanges = 0
        visualCanvas.onChange = { visualChanges += 1 }
        func image(_ view: MapCanvas) -> Data {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 700,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            view.displayIgnoringOpacity(view.bounds, in: context)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using: .png, properties: [:])!
        }
        let sourceFrame = mapLayout(visualModel.roots)[1].frame
        let startVisual = CGPoint(x: sourceFrame.midX + 80,
                                  y: visualCanvas.bounds.height - sourceFrame.midY - 90)
        visualCanvas.mouseDown(with: mouse(.leftMouseDown, startVisual))
        let pressed = image(visualCanvas)
        visualCanvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: startVisual.x + 3, y: startVisual.y)))
        assert(image(visualCanvas) == pressed, "Under 9pt must still be a click, not a drag")
        let whitespacePoint = CGPoint(x: 800, y: 380)
        visualCanvas.mouseDragged(with: mouse(.leftMouseDragged, whitespacePoint))
        assert(image(visualCanvas) != pressed, "Dragging into whitespace must visibly move a source ghost")
        assert(visualModel.roots == [visualRoot] && visualChanges == 0,
               "A drag must not edit the tree before release")
        visualCanvas.mouseUp(with: mouse(.leftMouseUp, whitespacePoint))
        assert(visualModel.roots == [visualRoot] && visualChanges == 0,
               "Invalid whitespace drop must preserve tree and dirty state")
        visualCanvas.mouseDown(with: mouse(.leftMouseDown, startVisual))
        let beforeCancel = image(visualCanvas)
        visualCanvas.mouseDragged(with: mouse(.leftMouseDragged, whitespacePoint))
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        visualCanvas.keyDown(with: escape)
        assert(image(visualCanvas) == beforeCancel, "Escape must clear a pending source ghost")
        visualCanvas.mouseUp(with: mouse(.leftMouseUp, whitespacePoint))
        assert(visualModel.roots == [visualRoot] && visualChanges == 0,
               "Cancelled drag must not create undo or dirty state")
        let rootFrame = mapLayout(visualModel.roots)[0].frame
        let rootStart = CGPoint(x: rootFrame.midX + 80,
                                y: visualCanvas.bounds.height - rootFrame.midY - 90)
        visualCanvas.mouseDown(with: mouse(.leftMouseDown, rootStart))
        let beforeRootPan = image(visualCanvas)
        visualCanvas.mouseDragged(with: mouse(.leftMouseDragged,
            CGPoint(x: rootStart.x + 45, y: rootStart.y + 28)))
        assert(image(visualCanvas) != beforeRootPan,
               "Grabbing the root must pan the visible map instead of silently failing")
        visualCanvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: rootStart.x + 45, y: rootStart.y + 28)))
        assert(visualModel.roots == [visualRoot] && visualChanges == 0)

        let longTitle = String(repeating: "Long title ", count: 12) + "\nSecond line"
        let fitRoot = MapNode(id: UUID(), title: "Root", children: (0..<3).map { group in
            MapNode(id: UUID(), title: "Group \(group) " + longTitle, children: (0..<2).map { leaf in
                MapNode(id: UUID(), title: "Leaf \(group).\(leaf) " + longTitle, children: [], folded: false)
            }, folded: false)
        }, folded: false) // One root, three groups, six leaves = ten nodes.
        let fitModel = MapModel(roots: [fitRoot], selected: fitRoot.id)
        let fitCanvas = MapCanvas(model: fitModel)
        fitCanvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 850)
        let fitted = fitCanvas.fitMapInView()
        assert(!fitted.isNull && fitted.minX >= 60 && fitted.minY >= 60)
        assert(fitted.maxX <= 1140 && fitted.maxY <= 790)
        assert(abs(fitted.midX - 600) < 2 && abs(fitted.midY - 425) < 2)
        assert(fitModel.roots == [fitRoot], "Viewport fitting must not change the tree")
        let beforePan = image(fitCanvas)
        fitCanvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 20, y: 20)))
        fitCanvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 45, y: 45)))
        fitCanvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 45, y: 45)))
        let afterPan = image(fitCanvas)
        assert(afterPan != beforePan && image(fitCanvas) == afterPan && fitModel.roots == [fitRoot],
               "Draw and ordinary pan must not automatically refit")
        let tall = MapCanvas(model: MapModel(roots: [longRoot], selected: longRoot.id))
        tall.frame = CGRect(x: 0, y: 0, width: 1200, height: 850)
        let tallBounds = tall.fitMapInView()
        let tallNodes = mapLayout([longRoot])
        let tallWorld = tallNodes.reduce(CGRect.null) { $0.union($1.frame) }
        let rootY = tallBounds.minY + (tallNodes[0].frame.midY - tallWorld.minY) * (tallBounds.width / tallWorld.width)
        assert(rootY >= 0 && rootY <= tall.bounds.height,
               "A tall map must keep its root visible at minimum zoom")
        let empty = MapCanvas(model: MapModel(roots: [], selected: UUID()))
        empty.frame = fitCanvas.frame
        assert(empty.fitMapInView().isNull)
        fitCanvas.frame.size.width = 128
        assert(fitCanvas.fitMapInView().isNull)
        print("canvas command, drag, pan and viewport-fit tests passed (no windows)")
    }
}
