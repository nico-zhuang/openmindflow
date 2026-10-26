import AppKit

@main
enum BlankCanvasPasteTests {
    static func main() throws {
        _ = NSApplication.shared
        let existing = MapNode(id: UUID(), title: "Do not overwrite me", children: [], folded: false,
                               location: SIMD2(130, 220))
        let canvas = MapCanvas(model: MapModel(roots: [existing], selected: existing.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1400, height: 720)
        var documentChanges = 0, selections = 0
        canvas.onChange = { documentChanges += 1 }
        canvas.onSelectionChange = { selections += 1 }
        let point = CGPoint(x: 940, y: 640)
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                               modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, at: point))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: point))
        assert(canvas.model.selectedIDs.isEmpty && canvas.model.roots == [existing] &&
               documentChanges == 0 && selections == 1,
               "Blank click must clear selection and announce it, without changing document or Undo")
        let board = NSPasteboard(name: NSPasteboard.Name("openmindflow-blank-text-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("A new independent idea", forType: .string)
        canvas.paste(from: board)
        guard canvas.model.roots.count == 2, let pasted = canvas.model.roots.last,
              pasted.title == "A new independent idea", pasted.children.isEmpty,
              pasted.location == SIMD2(860, 550), canvas.model.selectedIDs == [pasted.id] else {
            fatalError("Blank text paste must make exactly one independent anchored main node")
        }
        assert(canvas.model.roots[0] == existing && documentChanges == 1,
               "Blank paste must not mutate or attach to prior selected node")
        canvas.undo()
        assert(canvas.model.roots == [existing] && canvas.model.selectedIDs.isEmpty,
               "One Undo removes only the new root and restores blank selection")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 16,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<16 { for x in 0..<24 { bitmap.setColor(NSColor(deviceRed: 0.1, green: 0.7, blue: 0.7, alpha: 1), atX: x, y: y) } }
        let png = bitmap.representation(using: .png, properties: [:])!
        let images = NSPasteboard(name: NSPasteboard.Name("openmindflow-blank-image-\(UUID())"))
        defer { images.releaseGlobally() }
        images.clearContents()
        images.setData(png, forType: .png)
        canvas.paste(from: images)
        guard canvas.model.roots.count == 2, let imageRoot = canvas.model.roots.last else {
            fatalError("Blank image paste must create an independent main node")
        }
        assert(imageRoot.image?.data == png && imageRoot.location == SIMD2(860, 550) &&
               canvas.model.roots[0] == existing,
               "Image root must preserve verified PNG bytes and blank-click anchor")
        canvas.undo()
        assert(canvas.model.roots == [existing] && canvas.model.selectedIDs.isEmpty)
        canvas.model.selectOnly(existing.id)
        canvas.paste(from: images)
        assert(canvas.model.roots.count == 1 && canvas.model.roots[0].children.count == 1,
               "Pasting media with an explicitly selected node keeps child behavior")
        let second = MapNode(id: UUID(), title: "Other branch", children: [], folded: false,
                             location: SIMD2(130, 420))
        let reviewCanvas = MapCanvas(model: MapModel(roots: [existing, second], selected: existing.id))
        reviewCanvas.frame = canvas.frame
        let blank = CGPoint(x: 1050, y: 630)
        assert(reviewCanvas.menu(for: mouse(.rightMouseDown, at: blank)) != nil)
        assert(reviewCanvas.model.selectedIDs.isEmpty,
               "Blank right-click Paste must clear stale selection before opening context menu")
        let reviewBoard = NSPasteboard(name: NSPasteboard.Name("openmindflow-context-text-\(UUID())"))
        defer { reviewBoard.releaseGlobally() }
        reviewBoard.clearContents()
        reviewBoard.setString("Independent context idea", forType: .string)
        reviewCanvas.paste(from: reviewBoard)
        assert(reviewCanvas.model.roots.count == 3 && reviewCanvas.model.roots[0] == existing &&
               reviewCanvas.model.roots[2].title == "Independent context idea" &&
               reviewCanvas.model.roots[2].location == SIMD2(970, 540),
               "Context Paste on empty canvas must create a root at the right-click world anchor")
        reviewCanvas.undo()
        reviewCanvas.mouseDown(with: mouse(.leftMouseDown, at: blank))
        reviewCanvas.mouseUp(with: mouse(.leftMouseUp, at: blank))
        assert(reviewCanvas.model.selectedIDs.isEmpty)
        let arrowDown = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125)!
        reviewCanvas.keyDown(with: arrowDown)
        assert(reviewCanvas.model.selectedIDs.isEmpty,
               "Arrow navigation may not resurrect previous primary after explicit blank deselection")
        print("blank click/context menu deselect, text/image independent roots, arrow guard and undo passed")
    }
}
