import AppKit

@main enum CanvasGestureTests {
    static func main() {
        let child = MapNode(id: UUID(), title: "Child", children: [], folded: false,
                            location: SIMD2(400, 220))
        let root = MapNode(id: UUID(), title: "Root", children: [child], folded: false,
                           location: SIMD2(130, 220))
        let other = MapNode(id: UUID(), title: "Other", children: [], folded: false,
                            location: SIMD2(850, 220))
        let canvas = MapCanvas(model: MapModel(roots: [root, other], selected: root.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1400, height: 700)
        func send(_ type: NSEvent.EventType, _ point: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type,
                location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func key(_ text: String, code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        }
        func center(_ id: UUID) -> CGPoint { canvas.frameForAccessibility(id)!.center }
        let before = center(root.id), childBefore = center(child.id), otherBefore = center(other.id)
        let destination = CGPoint(x: before.x + 45, y: before.y + 35)
        canvas.mouseDown(with: send(.leftMouseDown, before))
        canvas.mouseDragged(with: send(.leftMouseDragged, destination))
        canvas.mouseUp(with: send(.leftMouseUp, destination))
        assert(center(root.id).distance(to: destination) < 1,
               "Dragging the root must move that root, not the viewport")
        assert(center(child.id).distance(to: CGPoint(x: childBefore.x + 45, y: childBefore.y + 35)) < 1,
               "Dragging the root must move its complete branch by the same delta")
        assert(center(other.id).distance(to: otherBefore) < 1,
               "A root branch drag must not pan or move unrelated roots")
        canvas.undo()
        assert(center(root.id).distance(to: before) < 1 && center(child.id).distance(to: childBefore) < 1,
               "One Undo must restore the complete root branch")

        let origin = CGPoint(x: 14, y: 95), corner = CGPoint(x: 615, y: 340)
        let rootBeforeMarquee = center(root.id)
        canvas.mouseDown(with: send(.leftMouseDown, origin))
        canvas.mouseDragged(with: send(.leftMouseDragged, corner))
        canvas.mouseUp(with: send(.leftMouseUp, corner))
        assert(canvas.model.selectedIDs == Set([root.id, child.id]),
               "Blank-area marquee selects all intersected nodes but excludes distant roots")
        assert(center(root.id).distance(to: rootBeforeMarquee) < 1,
               "Marquee must not pan the map")

        canvas.keyDown(with: key("h", code: 4))
        let panStart = CGPoint(x: 12, y: 550), panEnd = CGPoint(x: 50, y: 570)
        let panBefore = center(root.id), modelBefore = canvas.model.roots
        canvas.mouseDown(with: send(.leftMouseDown, panStart))
        canvas.mouseDragged(with: send(.leftMouseDragged, panEnd))
        canvas.mouseUp(with: send(.leftMouseUp, panEnd))
        assert(center(root.id).distance(to: CGPoint(x: panBefore.x + 38, y: panBefore.y + 20)) < 1,
               "H hand tool pans at exactly cursor displacement")
        assert(canvas.model.roots == modelBefore, "Panning must not edit the document or Undo history")
        canvas.keyDown(with: key("v", code: 9))
        let selectionBefore = center(root.id)
        canvas.mouseDown(with: send(.leftMouseDown, CGPoint(x: 10, y: 640)))
        canvas.mouseDragged(with: send(.leftMouseDragged, CGPoint(x: 60, y: 685)))
        canvas.mouseUp(with: send(.leftMouseUp, CGPoint(x: 60, y: 685)))
        assert(center(root.id).distance(to: selectionBefore) < 1,
               "V returns to selection tool; blank-area drag no longer pans")

        let middleBefore = center(root.id)
        let midStart = CGPoint(x: 15, y: 570), midEnd = CGPoint(x: 45, y: 610)
        func middle(_ kind: CGEventType, _ point: CGPoint) -> NSEvent {
            let cocoaY = canvas.bounds.height - point.y
            let event = CGEvent(mouseEventSource: nil, mouseType: kind,
                                mouseCursorPosition: CGPoint(x: point.x, y: NSScreen.main!.frame.maxY - cocoaY),
                                mouseButton: .center)!
            let native = NSEvent(cgEvent: event)!
            assert(native.buttonNumber == 2)
            return native
        }
        canvas.otherMouseDown(with: middle(.otherMouseDown, midStart))
        canvas.otherMouseDragged(with: middle(.otherMouseDragged, midEnd))
        canvas.otherMouseUp(with: middle(.otherMouseUp, midEnd))
        assert(center(root.id).distance(to: CGPoint(x: middleBefore.x + 30, y: middleBefore.y + 40)) < 1,
               "Holding middle button pans temporarily from selection mode")
        print("root subtree drag, marquee, H/V and middle-button pan passed")
    }
}

private extension CGPoint {
    var center: CGPoint { self }
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
