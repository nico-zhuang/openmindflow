import AppKit
import Darwin

@main
enum EditingJourney {
    static func main() throws {
        _ = NSApplication.shared // No window or event posting.
        let fm = FileManager.default
        let source = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Tests/Fixtures/MindMap-Closure-Sample.mindmap.json")
        let originalBytes = try Data(contentsOf: source)
        let original = try readOwnJSON(source)
        guard let root = original.first, original.count == 1, root.children.count == 3 else {
            fatalError("Expected the synthetic closure sample")
        }
        let model = MapModel(roots: original, selected: root.id)
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 1400, height: 1400)
        print("1 open synthetic own JSON")

        canvas.selectAndEdit(root.id)
        let titleField = canvas.subviews.compactMap { $0 as? NSTextField }.first!
        titleField.stringValue = "项目规划 · 已编辑 🧭"
        canvas.commitEditing()
        assert(model.roots[0].title == "项目规划 · 已编辑 🧭")
        print("2 rename via canvas editor")

        canvas.addChild()
        let childID = model.selected
        canvas.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "New branch"
        canvas.commitEditing()
        assert(model.roots[0].children.last?.id == childID)
        canvas.addSibling()
        let siblingID = model.selected
        canvas.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "Drag destination"
        canvas.commitEditing()
        assert(model.roots[0].children.suffix(2).map(\.id) == [childID, siblingID])
        print("3 add and name child + sibling")

        func key(_ code: UInt16, _ characters: String = "") -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        canvas.keyDown(with: key(123)) // Left to parent.
        assert(model.selected == root.id)
        canvas.keyDown(with: key(124)) // Right to first child.
        assert(model.selected == root.children[0].id)
        canvas.keyDown(with: key(123))
        assert(model.selected == root.id)
        print("4 navigate left/right locally")

        canvas.keyDown(with: key(49, " "))
        assert(model.roots[0].folded)
        canvas.undo()
        assert(!model.roots[0].folded)
        canvas.redo()
        assert(model.roots[0].folded)
        canvas.keyDown(with: key(49, " "))
        assert(!model.roots[0].folded)
        print("5 fold, undo, redo, unfold")

        let frames = mapLayout(model.roots)
        let sourceFrame = frames.first { $0.node.id == childID }!.frame
        let destinationFrame = frames.first { $0.node.id == siblingID }!.frame
        func point(_ frame: CGRect) -> CGPoint {
            CGPoint(x: frame.midX + 80, y: canvas.bounds.height - frame.midY - 90)
        }
        func mouse(_ kind: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, point(sourceFrame)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, point(destinationFrame)))
        canvas.mouseUp(with: mouse(.leftMouseUp, point(destinationFrame)))
        assert(model.roots[0].children.last?.children.map(\.id) == [childID])
        let dragged = model.roots
        canvas.undo()
        assert(model.roots[0].children.suffix(2).map(\.id) == [childID, siblingID])
        canvas.redo()
        assert(model.roots == dragged)
        print("6 local drag to sibling, undo/redo")

        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/editing-journey-XXXXXX").utf8CString
        let path = try pattern.withUnsafeMutableBufferPointer { buffer -> String in
            guard let start = buffer.baseAddress, let created = mkdtemp(start) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return String(cString: created)
        }
        let scratch = URL(fileURLWithPath: path, isDirectory: true)
        var info = stat()
        guard scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
              scratch.deletingLastPathComponent() == base,
              lstat(scratch.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Unsafe fixture directory") }
        defer { try? fm.removeItem(at: scratch) }
        let output = scratch.appendingPathComponent("journey.mindmap.json")
        try writeOwnJSON(model.roots, to: output)
        let reopened = try readOwnJSON(output)
        assert(reopened == model.roots)
        print("7 atomically save and reopen complete tree")

        let invalid = scratch.appendingPathComponent("invalid.mindmap.json")
        try Data("{bad".utf8).write(to: invalid)
        let active = model.roots
        do {
            model.roots = try readOwnJSON(invalid)
            fatalError("Invalid JSON accepted")
        } catch is DecodingError {
            assert(model.roots == active)
        }
        let sourceAfter = try Data(contentsOf: source)
        assert(sourceAfter == originalBytes, "Original fixture must remain untouched")
        print("8 malformed open rejected; active tree and source intact")
        print("editing journey passed (headless; window title and panels unverified)")
    }
}
