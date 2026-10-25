import AppKit

@main
enum CanvasCommandTests {
    static func main() {
        UserDefaults.standard.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
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
        if field.isBordered || field.drawsBackground || field.stringValue != "Existing" {
            fputs("Inline re-edit must use a readable native text field without restoring a card box\n", stderr)
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
        let returnRoot = MapNode(id: UUID(), title: "Root", children: [
            MapNode(id: UUID(), title: "Draft", children: [], folded: false)
        ], folded: false)
        let returnModel = MapModel(roots: [returnRoot], selected: returnRoot.children[0].id)
        let returnCanvas = MapCanvas(model: returnModel)
        returnCanvas.selectAndEdit(returnRoot.children[0].id)
        returnCanvas.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "Committed"
        assert(returnCanvas.control(control, textView: text,
            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        guard returnModel.roots[0].children.count == 1,
              returnModel.roots[0].children[0].title == "Committed",
              returnCanvas.subviews.compactMap({ $0 as? NSTextField }).isEmpty else {
            fputs("First Return must commit and close editor without creating a sibling\n", stderr); exit(1)
        }
        let plainReturn = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        returnCanvas.keyDown(with: plainReturn)
        assert(returnModel.roots[0].children.count == 2 &&
               returnCanvas.subviews.contains(where: { $0 is NSTextField }),
               "Second Return on canvas should create and edit a sibling")
        let freshCanvas = MapCanvas(model: MapModel(roots: [], selected: UUID()))
        freshCanvas.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        freshCanvas.addMainNode()
        let freshField = freshCanvas.subviews.compactMap { $0 as? NSTextField }.first!
        freshField.stringValue = "Hi"
        freshCanvas.commitEditing()
        let firstWidth = freshCanvas.model.roots[0].width
        assert(firstWidth != nil && firstWidth! >= 60 && firstWidth! < 170,
               "First text edit of a newly created node must set a compact measured width, not the old 170pt minimum")
        freshCanvas.undo()
        assert(freshCanvas.model.roots[0].title.isEmpty && freshCanvas.model.roots[0].width == nil,
               "First title and measured width need a single undo step")
        let rightA = MapNode(id: UUID(), title: "A", children: [], folded: false)
        let rightB = MapNode(id: UUID(), title: "B", children: [], folded: false)
        let rightRoot = MapNode(id: UUID(), title: "Root", children: [rightA, rightB], folded: false)
        let rightModel = MapModel(roots: [rightRoot], selected: rightA.id)
        let rightCanvas = MapCanvas(model: rightModel)
        rightCanvas.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        let rightBox = mapLayout(rightModel.roots).first { $0.node.id == rightB.id }!.frame
        let rightPoint = CGPoint(x: rightBox.midX + 80, y: 700 - rightBox.midY - 90)
        let rightEvent = NSEvent.mouseEvent(with: .rightMouseDown, location: rightPoint,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        guard let rightMenu = rightCanvas.menu(for: rightEvent), rightModel.selected == rightB.id,
              rightMenu.items.map(\.title) == ["Edit Title", "Copy", "Font…", "New Child", "New Sibling", "New Main Node", "Node Width", "Delete", "", "Arrange Map"] else {
            fputs("Right-clicking a node needs a context menu targeting that exact node\n", stderr); exit(1)
        }
        let editTitle = rightMenu.item(withTitle: "Edit Title")!
        assert(NSApp.sendAction(editTitle.action!, to: editTitle.target, from: editTitle) &&
               rightCanvas.subviews.contains(where: { $0 is NSTextField }),
               "Context Edit Title must open the existing native editor")
        rightCanvas.commitEditing()
        let widthMenu = rightMenu.item(withTitle: "Node Width")!.submenu!
        assert(widthMenu.item(withTitle: "Auto")?.state == .on)
        let medium = widthMenu.item(withTitle: "Medium (240 pt)")!
        assert(NSApp.sendAction(medium.action!, to: medium.target, from: medium) &&
               rightModel.roots[0].children[1].width == 240 &&
               mapLayout(rightModel.roots).first(where: { $0.node.id == rightB.id })!.frame.width == 240)
        assert(rightModel.undo() && rightModel.roots[0].children[1].width == nil,
               "Width presets must use the same undo stack as all other node edits")
        let blankRight = NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: 800, y: 40),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 1)!
        let menu = rightCanvas.menu(for: blankRight)!
        let expectedBlank = ["New Main Node", "Paste", "", "Zoom In", "Zoom Out", "Fit Content", "", "Select All", "", "Arrange Map"]
        assert(menu.items.map(\.title) == expectedBlank.map { $0.isEmpty ? "" : L10n.text($0, defaults: rightCanvas.localizationDefaults) },
               "Blank canvas must expose original-style zoom/fit/select groups without pretending a node was clicked")
        let beforeZoom = rightCanvas.frameForAccessibility(rightB.id)!
        let zoomIn = menu.item(withTitle: L10n.text("Zoom In", defaults: rightCanvas.localizationDefaults))!
        assert(NSApp.sendAction(zoomIn.action!, to: zoomIn.target, from: zoomIn) &&
               rightCanvas.frameForAccessibility(rightB.id)!.width > beforeZoom.width)
        let blankZoomOut = menu.item(withTitle: L10n.text("Zoom Out", defaults: rightCanvas.localizationDefaults))!
        assert(NSApp.sendAction(blankZoomOut.action!, to: blankZoomOut.target, from: blankZoomOut) &&
               abs(rightCanvas.frameForAccessibility(rightB.id)!.width - beforeZoom.width) < 0.01)
        let blankFit = menu.item(withTitle: L10n.text("Fit Content", defaults: rightCanvas.localizationDefaults))!
        assert(NSApp.sendAction(blankFit.action!, to: blankFit.target, from: blankFit))
        let selectAll = menu.item(withTitle: L10n.text("Select All", defaults: rightCanvas.localizationDefaults))!
        assert(NSApp.sendAction(selectAll.action!, to: selectAll.target, from: selectAll) &&
               rightModel.selectedIDs == [rightRoot.id, rightA.id, rightB.id],
               "Blank-canvas Select All must select visible nodes without mutating map content")
        let suiteName = "local.mindmap.appearance-test.\(UUID().uuidString)"
        let appearanceDefaults = UserDefaults(suiteName: suiteName)!
        let priorAppearance = NSApp.appearance
        func failAppearance(_ message: String) -> Never {
            appearanceDefaults.removePersistentDomain(forName: suiteName)
            NSApp.appearance = priorAppearance
            fputs("\(message)\n", stderr)
            exit(1)
        }
        defer {
            NSApp.appearance = priorAppearance
            appearanceDefaults.removePersistentDomain(forName: suiteName)
        }
        let appDelegate = AppDelegate(defaults: appearanceDefaults)
        _ = appDelegate.makeWorkbench(canvas: canvas)
        appDelegate.installMenu()
        assert(NSApp.mainMenu!.items.map(\.title) == ["MindMap", "File", "Edit", "View", "Node"])
        guard let editMenu = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu else {
            fputs("Missing Edit menu\n", stderr)
            exit(1)
        }
        let textCommands = [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")]
        let missingCommands = textCommands.filter { editMenu.item(withTitle: $0.0) == nil }.map { $0.0 }
        if !missingCommands.isEmpty {
            fputs("Missing native Edit commands: \(missingCommands.joined(separator: ", "))\n", stderr)
            exit(1)
        }
        for (title, action, key) in textCommands {
            let item = editMenu.item(withTitle: title)!
            if item.action.map(NSStringFromSelector) != action || item.keyEquivalent != key ||
                item.keyEquivalentModifierMask != [.command] || item.target != nil {
                fputs("\(title) must use \(action), Command-\(key.uppercased()), and a nil responder-chain target\n", stderr)
                exit(1)
            }
        }
        let viewMenu = NSApp.mainMenu!.items.compactMap(\.submenu).first { $0.title == "View" }!
        let outlineToggle = viewMenu.item(withTitle: "Show/Hide Outline")!
        guard let appearance = viewMenu.item(withTitle: "Appearance")?.submenu,
              appearance.items.map(\.title) == ["System", "Light", "Dark"] else {
            failAppearance("View → Appearance must offer System, Light, and Dark")
        }
        assert(outlineToggle.keyEquivalent == "s")
        assert(outlineToggle.keyEquivalentModifierMask == [.option, .command])
        assert(outlineToggle.action.map(NSStringFromSelector) == "toggleOutline:")
        assert(outlineToggle.target as AnyObject? === appDelegate)
        let fileMenu = NSApp.mainMenu!.items.compactMap(\.submenu).first { $0.title == "File" }!
        guard let mindNodeOpen = fileMenu.item(withTitle: "Open MindNode (Read-only)…"),
              let ownJSONOpen = fileMenu.item(withTitle: "Open Own JSON…"),
              mindNodeOpen.keyEquivalent == "o", mindNodeOpen.keyEquivalentModifierMask == [.command, .shift],
              mindNodeOpen.action.map(NSStringFromSelector) == "openMindNode:",
              mindNodeOpen.target as AnyObject? === appDelegate,
              ownJSONOpen.keyEquivalent == "o", ownJSONOpen.keyEquivalentModifierMask == [.command],
              ownJSONOpen.action.map(NSStringFromSelector) == "openFile:",
              ownJSONOpen.target as AnyObject? === appDelegate else {
            fputs("File shortcuts must be Cmd+O Own JSON and Cmd+Shift+O read-only MindNode, preserving actions and targets\n", stderr)
            exit(1)
        }
        let mindNodeCopy = fileMenu.item(withTitle: "Experimental MindNode v9 Plain-Tree Copy…")
        assert(mindNodeCopy?.action.map(NSStringFromSelector) == "exportMindNodeCopy:" &&
               mindNodeCopy?.target as AnyObject? === appDelegate,
               "The limited v9 writer must be available only as an explicitly experimental new-copy export")
        let nodeMenu = NSApp.mainMenu!.items.compactMap(\.submenu).first { $0.title == "Node" }!
        let fontMenu = nodeMenu.item(withTitle: "Font…")
        assert(fontMenu?.keyEquivalent == "t" && fontMenu?.keyEquivalentModifierMask == [.command],
               "Per-node native font panel must also be discoverable from Node menu via standard Command-T")
        let siblingMenu = nodeMenu.item(withTitle: "New Sibling")!
        assert(siblingMenu.keyEquivalent.isEmpty,
               "Plain Return must not be a global menu accelerator that preempts the text editor")
        let before = nodeMenu.item(withTitle: "New Sibling Before")!
        assert(before.keyEquivalent == "\r" && before.keyEquivalentModifierMask == [.option])
        let parent = nodeMenu.item(withTitle: "New Parent")!
        assert(parent.keyEquivalent == "\t" && parent.keyEquivalentModifierMask == [.option])
        let main = nodeMenu.item(withTitle: "New Main Node")!
        assert(main.keyEquivalent == "n" && main.keyEquivalentModifierMask == [.command],
               "New Main Node needs the native Command-N equivalent")
        let shortcutRoot = MapNode(id: UUID(), title: "Root", children: [], folded: false)
        let shortcutModel = MapModel(roots: [shortcutRoot], selected: shortcutRoot.id)
        let shortcutCanvas = MapCanvas(model: shortcutModel)
        let commandN = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: 0, context: nil, characters: "n",
            charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45)!
        shortcutCanvas.keyDown(with: commandN)
        assert(shortcutModel.roots.count == 2 && shortcutModel.selected == shortcutModel.roots[1].id &&
               shortcutCanvas.subviews.contains(where: { $0 is NSTextField }),
               "Command-N should add and edit one main/root node")
        let toolbar = appDelegate.makeToolbar()
        let identifiers = appDelegate.toolbarDefaultItemIdentifiers(toolbar).filter { $0 != .flexibleSpace }
        assert(identifiers.map(\.rawValue) == ["new-main", "new-child", "new-sibling", "fold-node", "fit-map", "outline", "style", "undo", "redo"])
        for (index, pair) in zip(identifiers,
                                 ["newMainNode:", "newChild:", "newSibling:", "foldNode:", "fitMap:", "toggleOutline:", "toggleStyle:", "undoEdit:", "redoEdit:"]).enumerated() {
            let (identifier, action) = pair
            let item = appDelegate.toolbar(toolbar, itemForItemIdentifier: identifier,
                                           willBeInsertedIntoToolbar: true)!
            assert(item.target as AnyObject? === appDelegate)
            assert(item.action.map(NSStringFromSelector) == action)
            assert(item.label == ["New Main Node", "New Child", "New Sibling", "Fold/Unfold", "Fit Map", "Show/Hide Outline", "Show/Hide Style", "Undo", "Redo"][index])
            assert(!(item.toolTip ?? "").isEmpty)
        }
        func selectedAppearance(_ menu: NSMenu) -> [String] {
            menu.items.filter { $0.state == .on }.map(\.title)
        }
        guard selectedAppearance(appearance) == ["System"], NSApp.appearance == nil else {
            failAppearance("System appearance must be the default with no app override")
        }
        for (title, name) in [("Dark", NSAppearance.Name.darkAqua), ("Light", .aqua)] {
            let item = appearance.item(withTitle: title)!
            guard let action = item.action, NSApp.sendAction(action, to: item.target, from: item),
                  NSApp.appearance?.name == name,
                  NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name,
                  selectedAppearance(appearance) == [title] else {
                failAppearance("Appearance choice \(title) must apply and be exclusively checked")
            }
        }
        let dark = appearance.item(withTitle: "Dark")!
        _ = NSApp.sendAction(dark.action!, to: dark.target, from: dark)
        let restored = AppDelegate(defaults: appearanceDefaults)
        _ = restored.makeWorkbench(canvas: MapCanvas(model: MapModel(roots: [], selected: UUID())))
        restored.installMenu()
        guard NSApp.appearance?.name == .darkAqua,
              let restoredMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu?
                .item(withTitle: "Appearance")?.submenu,
              selectedAppearance(restoredMenu) == ["Dark"] else {
            failAppearance("Appearance choice must persist across delegate launch")
        }
        guard let system = restoredMenu.item(withTitle: "System"), let action = system.action,
              NSApp.sendAction(action, to: system.target, from: system),
              NSApp.appearance == nil, selectedAppearance(restoredMenu) == ["System"] else {
            failAppearance("System appearance must return control to macOS")
        }
        appearanceDefaults.set("invalid", forKey: "appearance")
        let invalid = AppDelegate(defaults: appearanceDefaults)
        _ = invalid.makeWorkbench(canvas: MapCanvas(model: MapModel(roots: [], selected: UUID())))
        invalid.installMenu()
        guard NSApp.appearance == nil,
              let invalidMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu?
                .item(withTitle: "Appearance")?.submenu,
              selectedAppearance(invalidMenu) == ["System"] else {
            failAppearance("Invalid persisted appearance must fall back to System")
        }
        appearanceDefaults.removePersistentDomain(forName: suiteName)
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
        let repelSource = MapNode(id: UUID(), title: "Repel source", children: [], folded: false)
        let repelTarget = MapNode(id: UUID(), title: "Repel target", children: [], folded: false)
        let repelModel = MapModel(roots: [MapNode(id: UUID(), title: "Repel root",
            children: [repelSource, repelTarget], folded: false)], selected: repelSource.id)
        let repelCanvas = MapCanvas(model: repelModel)
        repelCanvas.frame = dragCanvas.frame
        let repelRows = mapLayout(repelModel.roots)
        let sourceBox = repelRows.first { $0.node.id == repelSource.id }!.frame
        let targetBox = repelRows.first { $0.node.id == repelTarget.id }!.frame
        let repelStart = CGPoint(x: sourceBox.midX + 80, y: repelCanvas.bounds.height - sourceBox.midY - 90)
        let nearTarget = CGPoint(x: targetBox.midX + 80, y: repelCanvas.bounds.height - targetBox.minY + 1 - 90)
        repelCanvas.mouseDown(with: mouse(.leftMouseDown, repelStart))
        repelCanvas.mouseDragged(with: mouse(.leftMouseDragged, nearTarget))
        guard let movingNear = repelCanvas.frameForAccessibility(repelSource.id),
              let targetNear = repelCanvas.frameForAccessibility(repelTarget.id),
              !movingNear.intersects(targetNear), repelModel.roots[0].children.count == 2 else {
            fputs("Nearby sibling cards must repel without overlap or early reparenting\n", stderr); exit(1)
        }
        repelCanvas.mouseUp(with: mouse(.leftMouseUp, nearTarget))
        let edgeStart = CGPoint(x: sourceBox.maxX - 5 + 80, y: repelStart.y)
        let slightOverlap = CGPoint(x: targetBox.minX + 5 + 80, y: repelCanvas.bounds.height - targetBox.midY - 90)
        repelCanvas.mouseDown(with: mouse(.leftMouseDown, edgeStart))
        repelCanvas.mouseDragged(with: mouse(.leftMouseDragged, slightOverlap))
        repelCanvas.mouseUp(with: mouse(.leftMouseUp, slightOverlap))
        if repelModel.roots[0].children.count != 2 {
            fputs("Cursor inside target must not reparent without large dragged-card overlap\n", stderr); exit(1)
        }
        let childLeaf = MapNode(id: UUID(), title: "Dragged leaf", children: [], folded: false)
        let childSource = MapNode(id: UUID(), title: "Dragged parent", children: [childLeaf,
            MapNode(id: UUID(), title: "Other A", children: [], folded: false),
            MapNode(id: UUID(), title: "Other B", children: [], folded: false)], folded: false)
        let targetLeaf = MapNode(id: UUID(), title: "Target leaf", children: [], folded: false)
        let targetMiddle = MapNode(id: UUID(), title: "Unrelated target leaf", children: [], folded: false)
        let childParent = MapNode(id: UUID(), title: "Target parent", children: [targetLeaf, targetMiddle], folded: false)
        let childModel = MapModel(roots: [MapNode(id: UUID(), title: "Root",
            children: [childSource, childParent], folded: false)], selected: childSource.id)
        let childCanvas = MapCanvas(model: childModel)
        let childWindow = NSWindow(contentRect: dragCanvas.frame, styleMask: [.titled],
            backing: .buffered, defer: false)
        childWindow.contentView = childCanvas // Attached, never shown or activated.
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        let childRows = mapLayout(childModel.roots)
        let childStartBox = childRows.first { $0.node.id == childSource.id }!.frame
        let childTargetBox = childRows.first { $0.node.id == childParent.id }!.frame
        let childStart = CGPoint(x: childStartBox.midX + 80,
                                 y: childCanvas.bounds.height - childStartBox.midY - 90)
        let childHover = CGPoint(x: childTargetBox.midX + 80,
                                 y: childCanvas.bounds.height - childTargetBox.midY - 90 + 10)
        childCanvas.mouseDown(with: mouse(.leftMouseDown, childStart))
        childCanvas.mouseDragged(with: mouse(.leftMouseDragged, childHover))
        let childFrames = childSource.children.compactMap { childCanvas.frameForAccessibility($0.id) }
        let targetFrames = childParent.children.compactMap { childCanvas.frameForAccessibility($0.id) }
        if childFrames.contains(where: { moved in targetFrames.contains(where: moved.intersects) }) {
            fputs("Child-hover may overlap its target card, not an unrelated descendant\n", stderr); exit(1)
        }
        childCanvas.mouseUp(with: mouse(.leftMouseUp, childHover))
        assert(childModel.roots[0].children.map(\.id) == [childParent.id] &&
               childModel.roots[0].children[0].children.last?.id == childSource.id,
               "Descendant non-overlap must be checked during a real child-drop preview")
        childWindow.orderOut(nil)
        let linkedLeaf = MapNode(id: UUID(), title: "Linked leaf", children: [], folded: false)
        let linkedBranch = MapNode(id: UUID(), title: "Linked branch",
            children: [linkedLeaf], folded: false)
        let linkedSource = MapNode(id: UUID(), title: "Cross columns", children: [], folded: false)
        let linkedModel = MapModel(roots: [MapNode(id: UUID(), title: "Root",
            children: [linkedSource, linkedBranch], folded: false)], selected: linkedSource.id)
        let linkedCanvas = MapCanvas(model: linkedModel)
        linkedCanvas.frame = dragCanvas.frame
        let linkedRows = mapLayout(linkedModel.roots)
        let linkedStartBox = linkedRows.first { $0.node.id == linkedSource.id }!.frame
        let parentBox = linkedRows.first { $0.node.id == linkedBranch.id }!.frame
        let leafBox = linkedRows.first { $0.node.id == linkedLeaf.id }!.frame
        let linkedStart = CGPoint(x: linkedStartBox.midX + 80,
                                  y: linkedCanvas.bounds.height - linkedStartBox.midY - 90)
        let acrossColumns = CGPoint(x: parentBox.maxX - 50 + linkedStartBox.width / 2 + 80,
                                    y: linkedCanvas.bounds.height - parentBox.midY - 90)
        linkedCanvas.mouseDown(with: mouse(.leftMouseDown, linkedStart))
        linkedCanvas.mouseDragged(with: mouse(.leftMouseDragged, acrossColumns))
        guard let parentDrawn = linkedCanvas.frameForAccessibility(linkedBranch.id),
              let leafDrawn = linkedCanvas.frameForAccessibility(linkedLeaf.id),
              abs((leafDrawn.midY - parentDrawn.midY) - (leafBox.midY - parentBox.midY)) < 0.01 else {
            fputs("Repelling across columns must move one stationary branch only once\n", stderr); exit(1)
        }
        let tallA = MapNode(id: UUID(), title: "Tall A", children: (0..<3).map {
            MapNode(id: UUID(), title: "A\($0)", children: [], folded: false)
        }, folded: false)
        let tallB = MapNode(id: UUID(), title: "Tall B", children: (0..<3).map {
            MapNode(id: UUID(), title: "B\($0)", children: [], folded: false)
        }, folded: false)
        let cascadeSource = MapNode(id: UUID(), title: "Drag", children: [], folded: false)
        let cascadeModel = MapModel(roots: [MapNode(id: UUID(), title: "Root",
            children: [cascadeSource, tallA, tallB], folded: false)], selected: cascadeSource.id)
        let cascadeCanvas = MapCanvas(model: cascadeModel)
        cascadeCanvas.frame = dragCanvas.frame
        let cascadeRows = mapLayout(cascadeModel.roots)
        let sourceStart = cascadeRows.first { $0.node.id == cascadeSource.id }!.frame
        let firstBranch = cascadeRows.first { $0.node.id == tallA.id }!.frame
        let cascadeStart = CGPoint(x: sourceStart.midX + 80, y: cascadeCanvas.bounds.height - sourceStart.midY - 90)
        let cascadeHover = CGPoint(x: firstBranch.midX + 80,
                                   y: cascadeCanvas.bounds.height - firstBranch.minY - 6 - 90)
        cascadeCanvas.mouseDown(with: mouse(.leftMouseDown, cascadeStart))
        cascadeCanvas.mouseDragged(with: mouse(.leftMouseDragged, cascadeHover))
        guard let bottomA = cascadeCanvas.frameForAccessibility(tallA.children.last!.id),
              let topB = cascadeCanvas.frameForAccessibility(tallB.children.first!.id),
              !bottomA.intersects(topB) else {
            fputs("Repelling a tall branch must not push its descendants into the next branch\n", stderr); exit(1)
        }
        cascadeCanvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
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
        let nestedLeaf = MapNode(id: UUID(), title: "Nested leaf", children: [], folded: false)
        let crossSource = MapNode(id: UUID(), title: "Move into gap", children: [nestedLeaf], folded: false)
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
        let beforeReflow = image(crossCanvas)
        crossCanvas.mouseDragged(with: mouse(.leftMouseDragged, crossGap))
        let duringReflow = image(crossCanvas)
        let shiftedGap = CGPoint(x: crossGap.x + 8, y: crossGap.y)
        crossCanvas.mouseDragged(with: mouse(.leftMouseDragged, shiftedGap))
        let shiftedReflow = image(crossCanvas)
        if crossModel.roots != beforeCrossMove || crossChanges != 0 || crossModel.undo() {
            fputs("A live layout preview must leave real tree, dirty callback and undo untouched\n", stderr); exit(1)
        }
        crossCanvas.mouseUp(with: mouse(.leftMouseUp, crossGap))
        let afterReflow = image(crossCanvas)
        func paintedInterior(_ data: Data, _ frame: CGRect) -> [NSColor] {
            guard let bitmap = NSBitmapImageRep(data: data) else { return [] }
            let x = Int(frame.minX + 80), y = Int(frame.minY + 90)
            guard x >= 0, y >= 0, x + Int(frame.width) < bitmap.pixelsWide,
                  y + Int(frame.height) < bitmap.pixelsHigh else { return [] }
            return stride(from: x + 12, through: x + Int(frame.width) - 12, by: 3).flatMap { column in
                stride(from: y + 9, through: y + Int(frame.height) - 9, by: 3).compactMap {
                    bitmap.colorAt(x: column, y: $0)
                }
            }
        }
        let committedRows = mapLayout(crossModel.roots)
        let shiftedSibling = committedRows.first { $0.node.id == leftChild.id }!.frame
        let nestedPosition = committedRows.first { $0.node.id == nestedLeaf.id }!.frame
        let beforeSibling = paintedInterior(beforeReflow, shiftedSibling)
        let afterSibling = paintedInterior(afterReflow, shiftedSibling)
        if afterSibling.isEmpty || beforeSibling == afterSibling {
            fputs("Destination sibling pixels must change at the new drawn position\n", stderr); exit(1)
        }
        if paintedInterior(duringReflow, shiftedSibling) != afterSibling ||
           paintedInterior(shiftedReflow, shiftedSibling) != afterSibling {
            fputs("Destination sibling must keep its live gap at both pointer positions\n", stderr); exit(1)
        }
        let sourceAtPointer = CGRect(x: crossGap.x - crossSourceFrame.width / 2 - 80,
            y: crossCanvas.bounds.height - crossGap.y - crossSourceFrame.height / 2 - 90,
            width: crossSourceFrame.width, height: crossSourceFrame.height)
        let originalNested = crossRows.first { $0.node.id == nestedLeaf.id }!.frame
        let nestedAtPointer = originalNested.offsetBy(dx: sourceAtPointer.minX - crossSourceFrame.minX,
                                                       dy: sourceAtPointer.minY - crossSourceFrame.minY)
        if paintedInterior(beforeReflow, crossSourceFrame) != paintedInterior(duringReflow, sourceAtPointer) ||
           paintedInterior(beforeReflow, originalNested) != paintedInterior(duringReflow, nestedAtPointer) {
            fputs("Dragged child and nested leaf must retain their original typography and text\n", stderr); exit(1)
        }
        for frame in [sourceAtPointer, nestedAtPointer] {
            let first = paintedInterior(duringReflow, frame)
            if first.isEmpty || first == paintedInterior(shiftedReflow, frame) ||
               first != paintedInterior(shiftedReflow, frame.offsetBy(dx: 8, dy: 0)) {
                fputs("Source and visible child must track the pointer exactly within one valid gap\n", stderr); exit(1)
            }
        }
        if paintedInterior(beforeReflow, nestedPosition) == paintedInterior(afterReflow, nestedPosition) ||
           paintedInterior(beforeReflow, crossSourceFrame) == paintedInterior(afterReflow, crossSourceFrame) {
            fputs("Committing the drag must move the entire source subtree to its new branch\n", stderr); exit(1)
        }
        if crossModel.roots[0].children.last?.children.map(\.id) != [leftChild.id, crossSource.id, rightChild.id] || crossChanges != 1 {
            fputs("Dragging into a different branch's child gap must insert there exactly once\n", stderr)
            exit(1)
        }
        if !crossModel.undo() || crossModel.roots != beforeCrossMove || crossModel.undo() {
            fputs("A single drag must add exactly one undo transaction\n", stderr); exit(1)
        }
        if !crossModel.redo() || crossModel.roots[0].children[0].children != [leftChild, crossSource, rightChild] ||
           !crossModel.undo() || crossModel.roots != beforeCrossMove {
            fputs("The nested subtree must survive the one-step redo and undo roundtrip\n", stderr); exit(1)
        }
        crossCanvas.mouseDown(with: mouse(.leftMouseDown, crossStart))
        let beforeEscape = image(crossCanvas)
        crossCanvas.mouseDragged(with: mouse(.leftMouseDragged, crossGap))
        crossCanvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        if image(crossCanvas) != beforeEscape || crossModel.roots != beforeCrossMove {
            fputs("Escape must restore the original canvas without changing its model\n", stderr); exit(1)
        }
        crossCanvas.mouseUp(with: mouse(.leftMouseUp, crossGap))
        crossCanvas.mouseDown(with: mouse(.leftMouseDown, crossStart))
        let beforeInvalidReflow = image(crossCanvas)
        crossCanvas.mouseDragged(with: mouse(.leftMouseDragged, crossGap))
        let blankPoint = CGPoint(x: 600, y: 300)
        crossCanvas.mouseDragged(with: mouse(.leftMouseDragged, blankPoint))
        let blankReflow = image(crossCanvas)
        if paintedInterior(blankReflow, beforeFrame) != paintedInterior(beforeInvalidReflow, beforeFrame) ||
           paintedInterior(blankReflow, afterFrame) != paintedInterior(beforeInvalidReflow, afterFrame) {
            fputs("Leaving a valid target must restore original sibling positions immediately\n", stderr); exit(1)
        }
        let sourceInBlank = CGRect(x: blankPoint.x - crossSourceFrame.width / 2 - 80,
            y: crossCanvas.bounds.height - blankPoint.y - crossSourceFrame.height / 2 - 90,
            width: crossSourceFrame.width, height: crossSourceFrame.height)
        let nestedInBlank = originalNested.offsetBy(dx: sourceInBlank.minX - crossSourceFrame.minX,
                                                    dy: sourceInBlank.minY - crossSourceFrame.minY)
        for (original, moved) in [(crossSourceFrame, sourceInBlank), (originalNested, nestedInBlank)] {
            if paintedInterior(beforeInvalidReflow, original) != paintedInterior(blankReflow, moved) ||
               paintedInterior(beforeInvalidReflow, original) == paintedInterior(blankReflow, original) {
                fputs("Source and visible descendants must follow into blank space without old copies\n", stderr); exit(1)
            }
        }
        crossCanvas.mouseUp(with: mouse(.leftMouseUp, blankPoint))
        if image(crossCanvas) != beforeInvalidReflow || crossModel.roots != beforeCrossMove || crossChanges != 1 {
            fputs("Invalid drop must clear reflow without dirtying or committing\n", stderr); exit(1)
        }
        crossCanvas.mouseDown(with: mouse(.leftMouseDown, crossStart))
        crossCanvas.mouseDragged(with: mouse(.leftMouseDragged, blankPoint))
        let directBlank = image(crossCanvas)
        if paintedInterior(directBlank, beforeFrame) != paintedInterior(beforeInvalidReflow, beforeFrame) ||
           paintedInterior(directBlank, afterFrame) != paintedInterior(beforeInvalidReflow, afterFrame) ||
           paintedInterior(directBlank, sourceInBlank) != paintedInterior(beforeInvalidReflow, crossSourceFrame) ||
           paintedInterior(directBlank, nestedInBlank) != paintedInterior(beforeInvalidReflow, originalNested) {
            fputs("Direct whitespace drag must carry whole subtree without moving siblings\n", stderr); exit(1)
        }
        crossCanvas.mouseUp(with: mouse(.leftMouseUp, blankPoint))
        if crossModel.roots != beforeCrossMove || crossChanges != 1 || image(crossCanvas) != beforeInvalidReflow {
            fputs("Releasing directly in whitespace must restore the complete original tree\n", stderr); exit(1)
        }
        func axNode(_ title: String) -> NSAccessibilityElement {
            (crossCanvas.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
                .first { $0.accessibilityLabel() == title }!
        }
        let sourceAX = axNode(crossSource.title), nestedAX = axNode(nestedLeaf.title), siblingAX = axNode(leftChild.title)
        let originalSourceAX = sourceAX.accessibilityFrame(), originalNestedAX = nestedAX.accessibilityFrame()
        let originalSiblingAX = siblingAX.accessibilityFrame()
        let siblingShift = shiftedSibling.minY - beforeFrame.minY
        assert(siblingShift != 0)
        crossCanvas.mouseDown(with: mouse(.leftMouseDown, crossStart))
        crossCanvas.mouseDragged(with: mouse(.leftMouseDragged, crossGap))
        let layoutsBeforeAX = mapLayoutInvocations
        let movingFrame = sourceAX.accessibilityFrame(), childFrame = nestedAX.accessibilityFrame()
        let shiftedFrame = siblingAX.accessibilityFrame()
        if mapLayoutInvocations - layoutsBeforeAX > 2 {
            fputs("Reading cached AX bounds must not repeat full map layout per node\n", stderr); exit(1)
        }
        if abs(movingFrame.minX - originalSourceAX.minX - (crossGap.x - crossStart.x)) > 0.01 ||
           abs(childFrame.minX - originalNestedAX.minX - (crossGap.x - crossStart.x)) > 0.01 ||
           abs(shiftedFrame.minY - originalSiblingAX.minY - siblingShift) > 0.01 {
            fputs("Cached AX node bounds must follow dragged subtree and live sibling reflow\n", stderr); exit(1)
        }
        crossCanvas.mouseDragged(with: mouse(.leftMouseDragged, blankPoint))
        if abs(sourceAX.accessibilityFrame().minX - originalSourceAX.minX - (blankPoint.x - crossStart.x)) > 0.01 ||
           siblingAX.accessibilityFrame() != originalSiblingAX {
            fputs("AX bounds must follow invalid whitespace drag while siblings return\n", stderr); exit(1)
        }
        crossCanvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        if sourceAX.accessibilityFrame() != originalSourceAX || nestedAX.accessibilityFrame() != originalNestedAX ||
           siblingAX.accessibilityFrame() != originalSiblingAX || crossModel.roots != beforeCrossMove {
            fputs("Cached AX bounds must restore on Escape without committing\n", stderr); exit(1)
        }
        crossCanvas.mouseUp(with: mouse(.leftMouseUp, blankPoint))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let springModel = MapModel(roots: beforeCrossMove, selected: crossSource.id)
            let springCanvas = MapCanvas(model: springModel)
            let springWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
            springWindow.contentView = springCanvas // Attached for native motion; never shown or made key.
            RunLoop.current.run(until: Date().addingTimeInterval(0.03)) // Drain initial window layout before counting spring ticks.
            let origin = springCanvas.frameForAccessibility(leftChild.id)!
            let sourceOrigin = springCanvas.frameForAccessibility(crossSource.id)!
            let childOrigin = springCanvas.frameForAccessibility(nestedLeaf.id)!
            let springStart = CGPoint(x: crossSourceFrame.midX + 80,
                                      y: springCanvas.bounds.height - crossSourceFrame.midY - 90)
            let springGap = CGPoint(x: beforeFrame.midX + 80,
                                    y: springCanvas.bounds.height - (beforeFrame.maxY + afterFrame.minY) / 2 - 90)
            springCanvas.mouseDown(with: mouse(.leftMouseDown, springStart))
            springCanvas.mouseDragged(with: mouse(.leftMouseDragged, springGap))
            let initial = springCanvas.frameForAccessibility(leftChild.id)!
            let targetY = origin.midY - siblingShift
            if abs(initial.midY - targetY) < 1 ||
               abs(springCanvas.frameForAccessibility(crossSource.id)!.minX - sourceOrigin.minX - (springGap.x - springStart.x)) > 0.01 ||
               abs(springCanvas.frameForAccessibility(nestedLeaf.id)!.minX - childOrigin.minX - (springGap.x - springStart.x)) > 0.01 ||
               springModel.roots != beforeCrossMove {
                fputs("Attached preview must initially ease siblings without lagging dragged subtree or mutating model\n", stderr); exit(1)
            }
            let layoutsBeforeTick = mapLayoutInvocations
            RunLoop.current.run(until: Date().addingTimeInterval(0.07))
            let intermediate = springCanvas.frameForAccessibility(leftChild.id)!
            if abs(intermediate.midY - targetY) >= abs(initial.midY - targetY) ||
               abs(intermediate.midY - targetY) < 0.1 || mapLayoutInvocations != layoutsBeforeTick {
                fputs("Spring tick must advance AX/painted sibling toward target without recomputing layout: initial=\(initial.midY), next=\(intermediate.midY), target=\(targetY), layouts=\(mapLayoutInvocations - layoutsBeforeTick)\n", stderr); exit(1)
            }
            springCanvas.advanceSpring(at: ProcessInfo.processInfo.systemUptime + 0.25)
            if abs(springCanvas.frameForAccessibility(leftChild.id)!.midY - targetY) >=
               abs(intermediate.midY - targetY) / 2 {
                fputs("A delayed spring tick must safely catch up using bounded real elapsed time\n", stderr); exit(1)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.65))
            let settled = springCanvas.frameForAccessibility(leftChild.id)!.midY
            let settledPaint = image(springCanvas)
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            if abs(settled - targetY) > 0.1 ||
               abs(springCanvas.frameForAccessibility(leftChild.id)!.midY - targetY) > 0.1 ||
               image(springCanvas) != settledPaint {
                fputs("Converged sibling must stay painted/AX at target until pointer moves or releases\n", stderr); exit(1)
            }
            springCanvas.mouseUp(with: mouse(.leftMouseUp, springGap))
            if springModel.roots[0].children.last?.children.map(\.id) != [leftChild.id, crossSource.id, rightChild.id] ||
               abs(springCanvas.frameForAccessibility(leftChild.id)!.midY - targetY) > 0.01 ||
               !springModel.undo() || springModel.roots != beforeCrossMove {
                fputs("Release must snap to canonical geometry and preserve single undoable move\n", stderr); exit(1)
            }
            springCanvas.needsDisplay = true // Undo changed the model without going through canvas.changed().
            springCanvas.mouseDown(with: mouse(.leftMouseDown, springStart))
            springCanvas.mouseDragged(with: mouse(.leftMouseDragged, springGap))
            _ = springCanvas.frameForAccessibility(leftChild.id)
            let blank = CGPoint(x: 1300, y: 40) // Outside every painted sibling; a nearby miss now intentionally repels.
            let blankEvent = mouse(.leftMouseDragged, blank)
            let blankLocal = springCanvas.convert(blankEvent.locationInWindow, from: nil)
            let beforeBlank = springCanvas.frameForAccessibility(crossSource.id)!
            springCanvas.mouseDragged(with: blankEvent)
            let blankDelta = blankLocal.x - springCanvas.convert(springGap, from: nil).x
            if abs(springCanvas.frameForAccessibility(crossSource.id)!.minX - beforeBlank.minX - blankDelta) > 0.01 {
                fputs("Every attached drag event must invalidate spring preview and keep the source 1:1\n", stderr); exit(1)
            }
            if springCanvas.frameForAccessibility(leftChild.id)! != origin {
                fputs("Invalid attached drag must immediately restore sibling geometry\n", stderr); exit(1)
            }
            springCanvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
            if springCanvas.frameForAccessibility(crossSource.id)! != sourceOrigin || springModel.roots != beforeCrossMove {
                fputs("Escape must cancel attached drag and clear its spring\n", stderr); exit(1)
            }
            springCanvas.mouseUp(with: mouse(.leftMouseUp, blank))
            let canonicalPaint = image(springCanvas)
            springCanvas.mouseDown(with: mouse(.leftMouseDown, springStart))
            springCanvas.mouseDragged(with: mouse(.leftMouseDragged, springGap))
            _ = springCanvas.frameForAccessibility(leftChild.id)
            springCanvas.mouseDown(with: mouse(.leftMouseDown, blank)) // Interrupt with a canonical-layout miss.
            if springCanvas.frameForAccessibility(leftChild.id)! != origin || image(springCanvas) != canonicalPaint {
                fputs("A no-hit mousedown must clear cached spring presentation and repaint canonical geometry\n", stderr); exit(1)
            }
            springCanvas.mouseUp(with: mouse(.leftMouseUp, blank))
            springCanvas.mouseDown(with: mouse(.leftMouseDown, springStart))
            springCanvas.mouseDragged(with: mouse(.leftMouseDragged, springGap))
            _ = springCanvas.frameForAccessibility(leftChild.id)
            springCanvas.advanceSpring(at: ProcessInfo.processInfo.systemUptime + 0.18)
            let painted = springCanvas.frameForAccessibility(leftChild.id)!
            if abs(painted.midY - origin.midY) <= origin.height / 2 {
                fputs("Synthetic moving sibling did not clear its canonical hit box\n", stderr); exit(1)
            }
            let hit = springWindow.convertFromScreen(painted)
            springCanvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: hit.midX, y: hit.midY)))
            if springModel.selected != leftChild.id || springCanvas.frameForAccessibility(leftChild.id)! != origin {
                fputs("Mousedown must select the painted moving sibling, then clear spring frames\n", stderr); exit(1)
            }
            springCanvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: hit.midX, y: hit.midY)))
            springWindow.orderOut(nil)
        }
        let centerParent = MapNode(id: UUID(), title: "Target", children: [], folded: false)
        let centerSource = MapNode(id: UUID(), title: "Dragged", children: [], folded: false)
        let centerModel = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [centerParent, centerSource], folded: false)],
                                   selected: centerSource.id)
        let centerCanvas = MapCanvas(model: centerModel)
        centerCanvas.frame = dragCanvas.frame
        let centerRows = mapLayout(centerModel.roots)
        let parentFrame = centerRows.first { $0.node.id == centerParent.id }!.frame
        let centerSourceFrame = centerRows.first { $0.node.id == centerSource.id }!.frame
        let centerStart = CGPoint(x: centerSourceFrame.midX + 80,
                                  y: centerCanvas.bounds.height - centerSourceFrame.midY - 90)
        let centerTarget = CGPoint(x: parentFrame.midX + 80, y: centerCanvas.bounds.height - parentFrame.midY - 90)
        func parentLinePixel(_ data: Data) -> NSColor? {
            let baseline = Int(parentFrame.maxY + 90 - 7)
            return NSBitmapImageRep(data: data)?.colorAt(x: Int(parentFrame.minX + 80 + 28),
                y: baseline)
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            centerCanvas.appearance = NSAppearance(named: appearance)
            centerCanvas.mouseDown(with: mouse(.leftMouseDown, centerStart))
            let noParentHover = image(centerCanvas)
            centerCanvas.mouseDragged(with: mouse(.leftMouseDragged, centerTarget))
            guard let before = parentLinePixel(noParentHover), let active = parentLinePixel(image(centerCanvas)),
                  before != active, centerModel.roots[0].children == [centerParent, centerSource] else {
                fputs("Center-parent drop needs an accent branch line in light and dark\n", stderr); exit(1)
            }
            centerCanvas.mouseUp(with: mouse(.leftMouseUp, centerStart))
            if parentLinePixel(image(centerCanvas)) != before || centerModel.roots[0].children != [centerParent, centerSource] {
                fputs("Invalid release must clear parent accent without committing\n", stderr); exit(1)
            }
        }
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
        let shortChildren = (0..<30).map { MapNode(id: UUID(), title: "N\($0)", children: [], folded: false) }
        let shortRoot = MapNode(id: UUID(), title: "Root", children: shortChildren, folded: false)
        let editCanvas = MapCanvas(model: MapModel(roots: [shortRoot], selected: shortChildren[0].id))
        var editChanges = 0
        editCanvas.onChange = { editChanges += 1 }
        editCanvas.frame = CGRect(x: 0, y: 0, width: 420, height: 260)
        let fit = editCanvas.fitMapInView(), world = mapLayout([shortRoot]).reduce(CGRect.null) { $0.union($1.frame) }
        guard abs(fit.width / world.width - 0.35) < 0.001 else {
            fputs("Thirty short child nodes must exercise minimum 0.35 zoom\n", stderr); exit(1)
        }
        let rootCanvas = MapCanvas(model: MapModel(roots: [shortRoot], selected: shortRoot.id))
        rootCanvas.frame = editCanvas.frame
        _ = rootCanvas.fitMapInView()
        rootCanvas.selectAndEdit(shortRoot.id)
        let layout = mapLayout([shortRoot])
        func rootPaintAvoidsChild() -> Bool {
            guard let field = rootCanvas.subviews.compactMap({ $0 as? NSTextField }).first,
                  let zoom = Mirror(reflecting: rootCanvas).children.first(where: { $0.label == "zoom" })?.value as? CGFloat,
                  zoom >= 0.8 - 0.001, field.frame.width >= 120, field.frame.height >= 22,
                  rootCanvas.bounds.insetBy(dx: 28, dy: 28).contains(field.frame) else { return false }
            let rootLeft = field.frame.minX - 12 * zoom
            let paintedRight = max(rootLeft + layout[0].frame.width * zoom, field.frame.maxX + 5)
            let childLeft = rootLeft + (layout[1].frame.minX - layout[0].frame.minX) * zoom
            return paintedRight + 2 <= childLeft
        }
        let initiallySeparated = rootPaintAvoidsChild()
        _ = rootCanvas.fitMapInView() // Toolbar Fit Map must not shrink an active editor back to 0.35.
        let refitSeparated = rootPaintAvoidsChild()
        let zoomOut = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                              wheelCount: 1, wheel1: -120, wheel2: 0, wheel3: 0)!
        zoomOut.flags = .maskCommand
        rootCanvas.scrollWheel(with: NSEvent(cgEvent: zoomOut)!) // Local event only; never posted.
        let wheelSeparated = rootPaintAvoidsChild()
        if !initiallySeparated || !refitSeparated || !wheelSeparated {
            fputs("Root editor must not paint into child column initial=\(initiallySeparated) fit=\(refitSeparated) zoomOut=\(wheelSeparated)\n", stderr)
            exit(1) // Expected RED without an assertion crash dialog.
        }
        rootCanvas.commitEditing()
        let idleFit = rootCanvas.fitMapInView()
        assert(abs(idleFit.width / world.width - 0.35) < 0.001,
               "Fit Map must retain the ordinary 0.35 minimum after editing ends")
        editCanvas.selectAndEdit(shortChildren[0].id)
        guard let editField = editCanvas.subviews.compactMap({ $0 as? NSTextField }).first,
              editField.frame.width >= 120, editField.frame.height >= 22,
              editCanvas.bounds.insetBy(dx: 28, dy: 28).contains(editField.frame) else {
            fputs("Low-zoom native editor must remain readable and inside viewport\n", stderr); exit(1)
        }
        let samples = [CGPoint(x: editField.frame.maxX + 5, y: editField.frame.midY),
                       CGPoint(x: editField.frame.midX, y: editField.frame.maxY + 2)]
        guard samples.allSatisfy(editCanvas.bounds.contains) else {
            fputs("No room to measure edit-state line\n", stderr); exit(1)
        }
        func paintedEditLine() -> [NSColor?] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 420, pixelsHigh: 260,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            editCanvas.draw(editCanvas.bounds) // Canvas paint only; exclude the native field subview.
            NSGraphicsContext.restoreGraphicsState()
            return samples.map { bitmap.colorAt(x: Int($0.x), y: Int(editCanvas.bounds.height - $0.y)) }
                + [bitmap.colorAt(x: 1, y: 1)] // Untouched canvas backdrop.
        }
        let editingColors = paintedEditLine()
        editCanvas.commitEditing()
        if editingColors[0] != editingColors[2] || editingColors[1] == editingColors[2] {
            fputs("Borderless native edit field needs clear surrounding canvas and a visible baseline\n", stderr)
            exit(1) // Expected RED without an assertion crash dialog.
        }
        assert(editCanvas.model.roots == [shortRoot] && editChanges == 0 && !editCanvas.model.undo(),
               "Editor paint must not mutate model or undo history")
        let oversized = MapNode(id: UUID(), title: String(repeating: "Long editable idea ", count: 80),
                                children: [], folded: false)
        let oversizedModel = MapModel(roots: [oversized], selected: oversized.id)
        let oversizedCanvas = MapCanvas(model: oversizedModel)
        oversizedCanvas.frame = smallCanvas.frame
        oversizedCanvas.selectAndEdit(oversized.id)
        let oversizedField = oversizedCanvas.subviews.compactMap { $0 as? NSTextField }.first!
        if !oversizedCanvas.bounds.insetBy(dx: 28, dy: 28).contains(oversizedField.frame) {
            fputs("Multiline native editor must stay entirely inside a narrow viewport\n", stderr)
            exit(1)
        }
        oversizedField.stringValue += "saved"
        oversizedCanvas.commitEditing()
        assert(oversizedModel.roots[0].title.hasSuffix("saved"))
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
        let rootBox = mapLayout(visualModel.roots).first!.frame
        let draggedBox = visualCanvas.frameForAccessibility(visualRoot.children[0].id)!
        let connectorMid = CGPoint(x: (rootBox.maxX + 80 + draggedBox.minX) / 2,
                                   y: (rootBox.midY + 90 + draggedBox.maxY - 7) / 2)
        let draggedBitmap = NSBitmapImageRep(data: image(visualCanvas))!
        let background = draggedBitmap.colorAt(x: 1, y: 1)!
        if !(-2...2).contains(where: { dy in (-2...2).contains(where: { dx in
            draggedBitmap.colorAt(x: Int(connectorMid.x) + dx, y: Int(connectorMid.y) + dy) != background
        }) }) {
            fputs("First-level dragged child must retain its parent connector through whitespace\n", stderr); exit(1)
        }
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
               "Grabbing the root must preview moving the complete branch")
        visualCanvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: rootStart.x + 45, y: rootStart.y + 28)))
        assert(visualModel.roots[0].location != nil && visualChanges == 1,
               "Releasing the root must persist a real branch move rather than pan the viewport")
        visualCanvas.undo()
        assert(visualModel.roots == [visualRoot], "One Undo restores the branch before dragging")
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
        let textLeft = projectedRoot.minX + 12 * fittedZoom
        let textWidth = projectedRoot.width - 24 * fittedZoom
        if abs(rootEditor.frame.minX - textLeft) >= 0.1 ||
            abs(rootEditor.frame.midY - projectedRoot.midY) >= 0.1 ||
            rootEditor.frame.width < textWidth || rootEditor.frame.height < 22 {
            fputs("Root editor must stay centered in its rectangle and preserve title width\n", stderr)
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
        print("canvas command, drag, pan and viewport-fit tests passed (no visible windows)")
    }
}
