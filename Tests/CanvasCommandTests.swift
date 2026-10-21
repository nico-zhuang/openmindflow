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
        appDelegate.installMenu()
        assert(NSApp.mainMenu!.items.map(\.title) == ["MindMap", "File", "Edit", "Node"])
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
        dragCanvas.mouseDown(with: mouse(.leftMouseDown, start))
        dragCanvas.mouseDragged(with: mouse(.leftMouseDragged, finish))
        dragCanvas.mouseUp(with: mouse(.leftMouseUp, finish))
        assert(dragging.roots[0].children.map(\.id) == [destinationID])
        assert(dragging.roots[0].children[0].children.map(\.id) == [movingID])
        assert(dragging.selected == movingID && changes == 1)
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
        print("canvas command, empty-map Return, drag, visibility, zoom/pan and Open menu tests passed (no windows)")
    }
}
