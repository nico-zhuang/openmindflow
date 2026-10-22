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
        if !field.isBordered || !field.drawsBackground {
            fputs("Inline re-edit must show a visible native text field, not an invisible overlay\n", stderr)
            exit(1)
        }
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
        assert(identifiers.map(\.rawValue) == ["new-child", "new-sibling", "fold-node", "fit-map", "undo", "redo"])
        for (index, pair) in zip(identifiers,
                                 ["newChild:", "newSibling:", "foldNode:", "fitMap:", "undoEdit:", "redoEdit:"]).enumerated() {
            let (identifier, action) = pair
            let item = appDelegate.toolbar(toolbar, itemForItemIdentifier: identifier,
                                           willBeInsertedIntoToolbar: true)!
            assert(item.target as AnyObject? === appDelegate)
            assert(item.action.map(NSStringFromSelector) == action)
            assert(item.label == ["New Child", "New Sibling", "Fold/Unfold", "Fit Map", "Undo", "Redo"][index])
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
        let gapRows = mapLayout(reordered.roots)
        let gapFrom = CGPoint(x: gapRows[1].frame.midX + 80,
                              y: reorderCanvas.bounds.height - gapRows[1].frame.midY - 90)
        let gap = CGPoint(x: gapRows[2].frame.midX + 80,
                          y: reorderCanvas.bounds.height - (gapRows[2].frame.maxY + gapRows[3].frame.minY) / 2 - 90)
        reorderCanvas.mouseDown(with: mouse(.leftMouseDown, gapFrom))
        reorderCanvas.mouseDragged(with: mouse(.leftMouseDragged, gap))
        reorderCanvas.mouseUp(with: mouse(.leftMouseUp, gap))
        if reordered.roots[0].children.map(\.id) != [siblingIDs[2], siblingIDs[0], siblingIDs[1]] {
            fputs("Dropping between siblings must reorder rather than be ignored\n", stderr)
            exit(1)
        }
        assert(reordered.undo() && reordered.roots[0].children.map(\.id) == [siblingIDs[0], siblingIDs[2], siblingIDs[1]])
        let crossSource = MapNode(id: UUID(), title: "Move into gap", children: [], folded: false)
        let leftChild = MapNode(id: UUID(), title: "Before", children: [], folded: false)
        let rightChild = MapNode(id: UUID(), title: "After", children: [], folded: false)
        let crossParent = MapNode(id: UUID(), title: "Destination", children: [leftChild, rightChild], folded: false)
        let crossModel = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [crossSource, crossParent], folded: false)],
                                  selected: crossSource.id)
        let crossCanvas = MapCanvas(model: crossModel)
        crossCanvas.frame = dragCanvas.frame
        let crossRows = mapLayout(crossModel.roots)
        let crossSourceFrame = crossRows.first { $0.node.id == crossSource.id }!.frame
        let beforeFrame = crossRows.first { $0.node.id == leftChild.id }!.frame
        let afterFrame = crossRows.first { $0.node.id == rightChild.id }!.frame
        let crossStart = CGPoint(x: crossSourceFrame.midX + 80,
                                 y: crossCanvas.bounds.height - crossSourceFrame.midY - 90)
        let crossGap = CGPoint(x: beforeFrame.midX + 80,
                               y: crossCanvas.bounds.height - (beforeFrame.maxY + afterFrame.minY) / 2 - 90)
        assert(crossModel.canMoveNode(crossSource.id, to: crossParent.id, at: 1))
        let beforeCrossMove = crossModel.roots
        var crossChanges = 0
        crossCanvas.onChange = { crossChanges += 1 }
        crossCanvas.mouseDown(with: mouse(.leftMouseDown, crossStart))
        crossCanvas.mouseDragged(with: mouse(.leftMouseDragged, crossGap))
        crossCanvas.mouseUp(with: mouse(.leftMouseUp, crossGap))
        if crossModel.roots[0].children.last?.children.map(\.id) != [leftChild.id, crossSource.id, rightChild.id] || crossChanges != 1 {
            fputs("Dragging into a different branch's child gap must insert there exactly once\n", stderr)
            exit(1)
        }
        assert(crossModel.undo() && crossModel.roots == beforeCrossMove)
        let tallBranch = MapNode(id: UUID(), title: "Tall", children: (0..<9).map {
            MapNode(id: UUID(), title: "Leaf \($0)", children: [], folded: false)
        }, folded: false)
        let next = MapNode(id: UUID(), title: "Next", children: [], folded: false)
        let last = MapNode(id: UUID(), title: "Last", children: [], folded: false)
        let farModel = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [tallBranch, next, last], folded: false)], selected: last.id)
        let farCanvas = MapCanvas(model: farModel)
        farCanvas.frame = dragCanvas.frame
        let farRows = mapLayout(farModel.roots)
        let firstBox = farRows.first { $0.node.id == tallBranch.id }!.frame
        let nextBox = farRows.first { $0.node.id == next.id }!.frame
        let lastBox = farRows.first { $0.node.id == last.id }!.frame
        let farStart = CGPoint(x: lastBox.midX + 80, y: farCanvas.bounds.height - lastBox.midY - 90)
        let distantGap = CGPoint(x: nextBox.midX + 80,
                                 y: farCanvas.bounds.height - (firstBox.maxY + nextBox.minY) / 2 - 90)
        farCanvas.mouseDown(with: mouse(.leftMouseDown, farStart))
        farCanvas.mouseDragged(with: mouse(.leftMouseDragged, distantGap))
        farCanvas.mouseUp(with: mouse(.leftMouseUp, distantGap))
        if farModel.roots[0].children.map(\.id) != [tallBranch.id, next.id, last.id] {
            fputs("Distant whitespace under a tall subtree must not reorder siblings\n", stderr)
            exit(1)
        }
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
        assert(distantEditor.font == mapFont(isRoot: false))
        smallCanvas.scrollWheel(with: localWheel(8, command: true)) // Local NSEvent only, never posted.
        assert(distantEditor.font == mapFont(isRoot: false, zoom: exp(0.08)))
        assert(distantEditor.font!.pointSize != firstSize,
               "Zooming during editing must scale the text field font with its node")
        let firstPosition = distantEditor.frame.origin
        smallCanvas.scrollWheel(with: localWheel(30))
        assert(distantEditor.frame.origin != firstPosition,
               "Panning during editing must keep the text field attached to its node")
        smallCanvas.scrollWheel(with: localWheel(-120, command: true))
        if distantEditor.frame.height < 22 || distantEditor.font!.pointSize < 11 {
            fputs("Bordered editor must remain readable at minimum canvas zoom\n", stderr)
            exit(1)
        }
        let multiline = MapNode(id: UUID(), title: "One\nTwo\nThree\nFour", children: [], folded: false)
        let multilineCanvas = MapCanvas(model: MapModel(roots: [multiline], selected: multiline.id))
        multilineCanvas.frame = dragCanvas.frame
        multilineCanvas.selectAndEdit(multiline.id)
        multilineCanvas.scrollWheel(with: localWheel(-120, command: true))
        let multilineField = multilineCanvas.subviews.compactMap { $0 as? NSTextField }.first!
        let textHeight = (multiline.title as NSString).boundingRect(
            with: CGSize(width: multilineField.frame.width - 8, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: multilineField.font!]).height
        if multilineField.frame.height < ceil(textHeight) + 6 {
            fputs("Bordered multiline editor must contain its text at minimum zoom\n", stderr)
            exit(1)
        }
        let deepLeaf = MapNode(id: UUID(), title: "Deep", children: [], folded: false)
        let deepBranch = MapNode(id: UUID(), title: "Branch", children: [deepLeaf], folded: false)
        let deepRoot = MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "Middle", children: [deepBranch], folded: false)
        ], folded: false)
        let edgeCanvas = MapCanvas(model: MapModel(roots: [deepRoot], selected: deepRoot.id))
        edgeCanvas.frame = CGRect(x: 0, y: 0, width: 420, height: 260)
        edgeCanvas.scrollWheel(with: localWheel(-120, command: true))
        edgeCanvas.selectAndEdit(deepLeaf.id)
        let edgeField = edgeCanvas.subviews.compactMap { $0 as? NSTextField }.first!
        if edgeField.frame.maxX > edgeCanvas.bounds.maxX - 28 + 0.1 {
            fputs("Expanded low-zoom editor must remain inside narrow canvas viewport: \(edgeField.frame) / \(edgeCanvas.bounds)\n", stderr)
            exit(1)
        }
        let wideNode = MapNode(id: UUID(), title: String(repeating: "Long idea ", count: 20), children: [], folded: false)
        let narrowCanvas = MapCanvas(model: MapModel(roots: [wideNode], selected: wideNode.id))
        narrowCanvas.frame = CGRect(x: 0, y: 0, width: 220, height: 300)
        narrowCanvas.scrollWheel(with: localWheel(-120, command: true))
        narrowCanvas.selectAndEdit(wideNode.id)
        let narrowField = narrowCanvas.subviews.compactMap { $0 as? NSTextField }.first!
        if narrowField.frame.width > narrowCanvas.bounds.width - 56 + 0.1 ||
            narrowField.frame.minX < 28 - 0.1 || narrowField.frame.maxX > narrowCanvas.bounds.maxX - 28 + 0.1 {
            fputs("Long-title editor cannot be wider than the visible narrow canvas\n", stderr)
            exit(1)
        }
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
        visualCanvas.selectAndEdit(visualRoot.id)
        assert(visualCanvas.subviews.compactMap { $0 as? NSTextField }.first!.font == mapFont(isRoot: true))
        visualCanvas.selectAndEdit(visualRoot.children[0].id)
        assert(visualCanvas.subviews.compactMap { $0 as? NSTextField }.first!.font == mapFont(isRoot: false))

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
        fitCanvas.selectAndEdit(fitRoot.id)
        let rootEditor = fitCanvas.subviews.compactMap { $0 as? NSTextField }.first!
        let worldWidth = mapLayout(fitModel.roots).reduce(CGRect.null) { $0.union($1.frame) }.width
        let refit = fitCanvas.fitMapInView() // Active editor must follow an explicit fit.
        let fittedZoom = refit.width / worldWidth
        assert(rootEditor.font == mapFont(isRoot: true, zoom: fittedZoom))
        assert(rootEditor.cell?.wraps == true && !rootEditor.usesSingleLineMode,
               "Native editor must preserve multiline text")
        let fittedWorld = mapLayout(fitModel.roots).reduce(CGRect.null) { $0.union($1.frame) }
        let rootWorld = mapLayout(fitModel.roots)[0].frame
        let projectedRoot = CGRect(x: refit.minX + (rootWorld.minX - fittedWorld.minX) * fittedZoom,
                                   y: refit.minY + (rootWorld.minY - fittedWorld.minY) * fittedZoom,
                                   width: rootWorld.width * fittedZoom, height: rootWorld.height * fittedZoom)
        let textArea = projectedRoot.insetBy(dx: 12 * fittedZoom, dy: 11 * fittedZoom)
        if abs(rootEditor.frame.minX - textArea.minX) >= 0.1 ||
            abs(rootEditor.frame.midY - projectedRoot.midY) >= 0.1 ||
            rootEditor.frame.width < textArea.width || rootEditor.frame.height < textArea.height {
            fputs("Active bordered editor must contain the painted label area and remain centered\n", stderr)
            exit(1)
        }
        fitCanvas.selectAndEdit(fitRoot.children[0].id)
        let branchEditor = fitCanvas.subviews.compactMap { $0 as? NSTextField }.first!
        assert(branchEditor.font == mapFont(isRoot: false, zoom: fittedZoom))
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

        let foldedBranch = MapNode(id: UUID(), title: "Branch", children: [
            MapNode(id: UUID(), title: "Hidden child", children: [], folded: false)
        ], folded: true)
        let plainLeaf = MapNode(id: UUID(), title: "Leaf", children: [], folded: false)
        let axRoot = MapNode(id: UUID(), title: "Root", children: [foldedBranch, plainLeaf], folded: false)
        let axCanvas = MapCanvas(model: MapModel(roots: [axRoot], selected: foldedBranch.id))
        func axState(_ title: String) -> String {
            let node = (axCanvas.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
                .first { $0.accessibilityLabel() == title }!
            return "\(node.accessibilityHelp() ?? "") \(node.accessibilityValue() ?? "")".lowercased()
        }
        if !axState("Branch").contains("collapsed") || !axState("Branch").contains("1 child") ||
            axState("Leaf").contains("collapsed") {
            fputs("Folded canvas branch must expose collapsed state and child count, unlike a leaf\n", stderr)
            exit(1) // Expected RED must not produce a macOS assertion/crash dialog.
        }
        axCanvas.toggleFold()
        if !axState("Branch").contains("expanded") {
            fputs("Unfolding a canvas branch must refresh its accessibility state\n", stderr)
            exit(1)
        }
        print("canvas command, drag, pan and viewport-fit tests passed (no windows)")
    }
}
