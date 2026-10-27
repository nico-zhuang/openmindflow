import AppKit

@main enum CanvasRootMediaReparentTests {
    static func main() throws {
        _ = NSApplication.shared // Detached canvas and a private synthetic image pasteboard only.
        let target = MapNode(id: UUID(), title: "Attach under me", children: [], folded: false)
        let main = MapNode(id: UUID(), title: "Main", children: [target], folded: false,
                           location: SIMD2(170, 220))
        let canvas = MapCanvas(model: MapModel(roots: [main], selected: main.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1500, height: 850)
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                               modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let blank = CGPoint(x: 1050, y: 210)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: blank))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: blank))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 16,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<16 { for x in 0..<24 {
            bitmap.setColor(NSColor(deviceRed: 0.1, green: 0.65, blue: 0.7, alpha: 1), atX: x, y: y)
        } }
        let png = bitmap.representation(using: .png, properties: [:])!
        let board = NSPasteboard(name: .init("openmindflow-root-reparent-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        assert(board.setData(png, forType: .png) && canvas.paste(from: board))
        let imageRoot = canvas.model.roots.last!
        assert(canvas.model.roots.count == 2 && imageRoot.image?.data == png && imageRoot.location != nil,
               "Blank paste creates an independent media root first")
        let prior = canvas.model.roots
        let start = canvas.frameForAccessibility(imageRoot.id)!.center
        let hover = canvas.frameForAccessibility(target.id)!.center
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: hover))
        assert(canvas.model.roots == prior, "Hover must preview without mutating the saved map")
        canvas.mouseUp(with: mouse(.leftMouseUp, at: hover))
        guard canvas.model.roots.count == 1,
              canvas.model.roots[0].children[0].children.map(\.id) == [imageRoot.id],
              canvas.model.roots[0].children[0].children[0].image?.data == png else {
            fatalError("A pasted image root dragged onto a child must attach instead of floating in place")
        }
        let imageFrame = canvas.frameForAccessibility(imageRoot.id)!
        let targetFrame = canvas.frameForAccessibility(target.id)!
        assert(!imageFrame.intersects(targetFrame), "Final reparented media must not obscure its target")
        canvas.undo()
        assert(canvas.model.roots == prior, "One Undo restores the pasted independent root")

        // An invalid hover over the edge of an occupied root cannot commit a stack of nodes.
        let fixed = MapNode(id: UUID(), title: "Stationary", children: [], folded: false,
                            location: SIMD2(650, 520))
        let loose = MapNode(id: UUID(), title: "Move without stacking", children: [], folded: false,
                            location: SIMD2(1000, 520))
        let freeCanvas = MapCanvas(model: MapModel(roots: [fixed, loose], selected: loose.id))
        freeCanvas.frame = canvas.frame
        func freeMouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type,
                location: CGPoint(x: point.x, y: freeCanvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let fixedBefore = freeCanvas.frameForAccessibility(fixed.id)!
        let freeStart = freeCanvas.frameForAccessibility(loose.id)!.center
        let occupiedEdge = CGPoint(x: fixedBefore.minX - 8, y: fixedBefore.midY)
        freeCanvas.mouseDown(with: freeMouse(.leftMouseDown, at: freeStart))
        freeCanvas.mouseDragged(with: freeMouse(.leftMouseDragged, at: occupiedEdge))
        freeCanvas.mouseUp(with: freeMouse(.leftMouseUp, at: occupiedEdge))
        assert(freeCanvas.frameForAccessibility(fixed.id)! == fixedBefore &&
               !freeCanvas.frameForAccessibility(loose.id)!.intersects(fixedBefore),
               "A free root dropped across another root's edge settles into a nearby vacancy")
        assert(freeCanvas.model.undo() && freeCanvas.model.roots == [fixed, loose],
               "Collision-safe final placement is one Undoable move")
        let leftNeighbor = MapNode(id: UUID(), title: "Left branch", children: [], folded: false,
                                   branchSide: "left")
        let center = MapNode(id: UUID(), title: "Center", children: [leftNeighbor], folded: false,
                             location: SIMD2(550, 430))
        var leftMedia = MapNode(id: UUID(), title: "Pasted visual", children: [], folded: false,
                                location: SIMD2(1050, 430))
        leftMedia.image = try MapImage(data: png)
        let leftCanvas = MapCanvas(model: MapModel(roots: [center, leftMedia], selected: leftMedia.id))
        leftCanvas.frame = canvas.frame
        func sideMouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type,
                location: CGPoint(x: point.x, y: leftCanvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let centerFrame = leftCanvas.frameForAccessibility(center.id)!
        let poster = leftCanvas.mediaRect(for: leftMedia.id)!
        let leftZone = CGPoint(x: centerFrame.minX + centerFrame.width * 0.35, y: centerFrame.midY)
        leftCanvas.mouseDown(with: sideMouse(.leftMouseDown,
            at: CGPoint(x: poster.midX, y: poster.midY)))
        leftCanvas.mouseDragged(with: sideMouse(.leftMouseDragged, at: leftZone))
        leftCanvas.mouseUp(with: sideMouse(.leftMouseUp, at: leftZone))
        assert(leftCanvas.model.roots.count == 1 &&
               leftCanvas.model.roots[0].children.last?.id == leftMedia.id &&
               leftCanvas.model.roots[0].children.last?.branchSide == "left" &&
               leftCanvas.frameForAccessibility(leftMedia.id)!.maxX < centerFrame.minX,
               "Dragging a free media root onto the left half of a root attaches it to the left")
        print("blank-pasted image root attaches to child/left root; invalid free move avoids final occlusion")
    }
}

private extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }
