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
        let workbench = appDelegate.makeWorkbench(canvas: canvas)
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
        assert(outlineToggle.action.map(NSStringFromSelector) == "toggleSidebar:")
        assert(outlineToggle.target as AnyObject? === workbench)
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
            let blank = CGPoint(x: 900, y: 40)
            springCanvas.mouseDragged(with: mouse(.leftMouseDragged, blank))
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
        func outerBorderPixel(_ data: Data) -> NSColor? {
            NSBitmapImageRep(data: data)?.colorAt(x: Int(parentFrame.minX + 80 + 20),
                y: Int(parentFrame.minY + 90 - 5))
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            centerCanvas.appearance = NSAppearance(named: appearance)
            centerCanvas.mouseDown(with: mouse(.leftMouseDown, centerStart))
            let noParentHover = image(centerCanvas)
            centerCanvas.mouseDragged(with: mouse(.leftMouseDragged, centerTarget))
            guard let before = outerBorderPixel(noParentHover), let active = outerBorderPixel(image(centerCanvas)),
                  before != active, centerModel.roots[0].children == [centerParent, centerSource] else {
                fputs("Center-parent drop needs an unobscured accent rim in light and dark\n", stderr); exit(1)
            }
            centerCanvas.mouseUp(with: mouse(.leftMouseUp, centerStart))
            if outerBorderPixel(image(centerCanvas)) != before || centerModel.roots[0].children != [centerParent, centerSource] {
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
        let borders = [CGPoint(x: editField.frame.maxX + 5, y: editField.frame.midY),
                       CGPoint(x: editField.frame.midX, y: editField.frame.maxY + 5)]
        guard borders.allSatisfy(editCanvas.bounds.contains) else {
            fputs("No room to measure edit-state borders\n", stderr); exit(1)
        }
        func paintedBorders() -> [NSColor?] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 420, pixelsHigh: 260,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            editCanvas.draw(editCanvas.bounds) // Canvas paint only; exclude the native field subview.
            NSGraphicsContext.restoreGraphicsState()
            return borders.map { bitmap.colorAt(x: Int($0.x), y: Int(editCanvas.bounds.height - $0.y)) }
                + [bitmap.colorAt(x: 1, y: 1)] // Untouched canvas backdrop.
        }
        let editingColors = paintedBorders()
        editCanvas.commitEditing()
        if editingColors[0] == editingColors[2] || editingColors[1] == editingColors[2] {
            fputs("Selected node paint must enclose the editor on right and bottom, not just the viewport\n", stderr)
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
        print("canvas command, drag, pan and viewport-fit tests passed (no visible windows)")
    }
}
