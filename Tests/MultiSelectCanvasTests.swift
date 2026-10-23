import AppKit

@main enum MultiSelectCanvasTests {
    static func main() {
        let a = MapNode(id: UUID(), title: "A", children: [], folded: false, width: 170)
        let b = MapNode(id: UUID(), title: "B", children: [], folded: false, width: 240)
        let target = MapNode(id: UUID(), title: "Target", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Root", children: [a, b, target], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: a.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 700)
        func event(_ type: NSEvent.EventType, _ id: UUID, flags: NSEvent.ModifierFlags = [],
                   dx: CGFloat = 0, dy: CGFloat = 0) -> NSEvent {
            let box = canvas.frameForAccessibility(id)!
            return mouse(type, x: box.midX + dx, y: box.midY + dy, flags: flags)
        }
        func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat,
                   flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: canvas.bounds.height - y),
                modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown, b.id, flags: [.shift]))
        canvas.mouseUp(with: event(.leftMouseUp, b.id, flags: [.shift]))
        assert(canvas.model.selectedIDs == Set([a.id, b.id]), "Shift-click must add a sibling without dropping the first selected node")
        let selectedAX: [NSAccessibilityElement] = canvas.accessibilityChildren()?.compactMap {
            $0 as? NSAccessibilityElement
        } ?? []
        assert(selectedAX.filter { $0.isAccessibilitySelected() }.count == 2,
               "Both selected text boxes must be accessible as selected nodes")
        let widthBox = canvas.frameForAccessibility(b.id)!
        let handleX = widthBox.maxX - 6, handleY = widthBox.minY + 5
        canvas.mouseDown(with: mouse(.leftMouseDown, x: handleX, y: handleY))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, x: handleX + 44, y: handleY))
        canvas.mouseUp(with: mouse(.leftMouseUp, x: handleX + 44, y: handleY))
        assert(canvas.model.roots[0].children[0].width == 214 && canvas.model.roots[0].children[1].width == 284,
               "Dragging any selected handle should grow both widths by the same 44pt delta")
        canvas.undo()
        assert(canvas.model.roots[0].children[0].width == 170 && canvas.model.roots[0].children[1].width == 240,
               "One undo must restore all selected widths")
        canvas.mouseDown(with: event(.leftMouseDown, b.id))
        let start = canvas.frameForAccessibility(b.id)!
        let end = canvas.frameForAccessibility(target.id)!
        canvas.mouseDragged(with: mouse(.leftMouseDragged, x: end.midX, y: end.midY))
        canvas.mouseUp(with: mouse(.leftMouseUp, x: end.midX, y: end.midY))
        assert(canvas.model.roots[0].children.last?.children.map(\.id) == [a.id, b.id],
               "Dragging one member of a multi-selection over a target must reparent the selected group in order")
        canvas.undo()
        assert(canvas.model.roots[0].children.map(\.id) == [a.id, b.id, target.id],
               "One undo restores the original parent/order for the entire moved group")
        canvas.mouseDown(with: event(.leftMouseDown, b.id, flags: [.command]))
        canvas.mouseUp(with: event(.leftMouseUp, b.id, flags: [.command]))
        assert(canvas.model.selectedIDs == Set([a.id]), "Command-click toggles only the clicked member")
        var placedA = a, placedB = b, placedRoot = root
        placedA.location = SIMD2(400, 180)
        placedB.location = SIMD2(400, 280)
        placedRoot.children = [placedA, placedB]
        placedRoot.location = SIMD2(100, 230)
        let positioned = MapCanvas(model: MapModel(roots: [placedRoot], selected: a.id))
        positioned.frame = CGRect(x: 0, y: 0, width: 1200, height: 700)
        func posMouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat,
                      flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 700 - y), modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let aBox = positioned.frameForAccessibility(a.id)!, bBox = positioned.frameForAccessibility(b.id)!
        positioned.mouseDown(with: posMouse(.leftMouseDown, x: bBox.midX, y: bBox.midY, flags: [.shift]))
        positioned.mouseUp(with: posMouse(.leftMouseUp, x: bBox.midX, y: bBox.midY, flags: [.shift]))
        positioned.mouseDown(with: posMouse(.leftMouseDown, x: aBox.midX, y: aBox.midY))
        positioned.mouseDragged(with: posMouse(.leftMouseDragged, x: aBox.midX + 40, y: aBox.midY + 30))
        positioned.mouseUp(with: posMouse(.leftMouseUp, x: aBox.midX + 40, y: aBox.midY + 30))
        assert(positioned.model.roots[0].children.map(\.location) == [SIMD2(440, 210), SIMD2(440, 310)],
               "Dragging selected nodes into free space must move all positioned nodes by the same delta")
        positioned.undo()
        assert(positioned.model.roots[0].children.map(\.location) == [SIMD2(400, 180), SIMD2(400, 280)],
               "One undo restores the group's exact original MindNode world coordinates")
        _ = start
        print("multi-selection, group resize/reparent/free move and undo passed")
    }
}
