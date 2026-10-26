import AppKit

@main
enum DragTargetLatchTests {
    static func main() {
        _ = NSApplication.shared
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            print("drag target latch test skipped: Reduce Motion is enabled")
            return
        }
        let leaves = (0..<5).map { MapNode(id: UUID(), title: "Source leaf \($0)", children: [], folded: false) }
        let source = MapNode(id: UUID(), title: "Tall source", children: leaves, folded: false)
        let target = MapNode(id: UUID(), title: "Moving target", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Root", children: [source, target], folded: false)
        let model = MapModel(roots: [root], selected: source.id)
        let canvas = MapCanvas(model: model)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1300, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas // Owned offscreen fixture; never shown or made key.
        let rows = mapLayout(model.roots)
        let sourceFrame = rows.first { $0.node.id == source.id }!.frame
        let targetFrame = rows.first { $0.node.id == target.id }!.frame
        let proposed = MapModel(roots: model.roots, selected: source.id)
        guard proposed.moveNode(source.id, to: target.id, at: 0),
              let proposedTarget = mapLayout(proposed.roots).first(where: { $0.node.id == target.id })?.frame,
              abs(proposedTarget.midY - targetFrame.midY) > 100 else {
            fputs("Fixture must have a legal child move that reflows target by over 100 points\n", stderr); exit(1)
        }
        func event(_ kind: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func center(_ frame: CGRect) -> CGPoint {
            CGPoint(x: frame.midX + 80, y: canvas.bounds.height - frame.midY - 90)
        }
        func paintedCenter() -> CGPoint {
            let rect = window.convertFromScreen(canvas.frameForAccessibility(target.id)!)
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        let original = model.roots
        var changes = 0
        canvas.onChange = { changes += 1 }
        let start = center(sourceFrame), firstHover = center(targetFrame)
        canvas.mouseDown(with: event(.leftMouseDown, at: start))
        canvas.mouseDragged(with: event(.leftMouseDragged, at: firstHover))
        guard model.roots == original, model.canMoveNode(source.id, to: target.id, at: 0) else {
            fputs("Fixture must begin with a genuine legal child drop and unchanged model\n", stderr); exit(1)
        }
        _ = canvas.frameForAccessibility(target.id)
        var followed = firstHover
        for step in 1...8 {
            canvas.advanceSpring(at: ProcessInfo.processInfo.systemUptime + Double(step) * 0.03)
            followed = paintedCenter()
            canvas.mouseDragged(with: event(.leftMouseDragged, at: followed))
            let after = paintedCenter()
            if hypot(after.x - firstHover.x, after.y - firstHover.y) < 1 && step > 2 {
                fputs("Painted drop candidate fled the pointer and reset during follow\n", stderr); exit(1)
            }
        }
        guard hypot(followed.x - firstHover.x, followed.y - firstHover.y) > 48 else {
            fputs("Painted candidate fled the pointer before following its >100pt reflow\n", stderr); exit(1)
        }
        canvas.mouseUp(with: event(.leftMouseUp, at: followed))
        guard model.roots[0].children.map(\.id) == [target.id],
              model.roots[0].children[0].children.map(\.id) == [source.id],
              changes == 1, model.undo(), model.roots == original else {
            fputs("Release near painted latched target must commit exactly one undoable child move\n", stderr); exit(1)
        }
        canvas.needsDisplay = true // Model undo happened outside the canvas command path.
        canvas.mouseDown(with: event(.leftMouseDown, at: start))
        canvas.mouseDragged(with: event(.leftMouseDragged, at: firstHover))
        _ = canvas.frameForAccessibility(target.id)
        canvas.advanceSpring(at: ProcessInfo.processInfo.systemUptime + 0.12)
        let farBlank = CGPoint(x: canvas.bounds.maxX - 20, y: 20)
        canvas.mouseDragged(with: event(.leftMouseDragged, at: farBlank))
        canvas.mouseUp(with: event(.leftMouseUp, at: farBlank))
        guard model.roots == original, changes == 1 else {
            fputs("A far blank release must discard rather than revive the previous candidate\n", stderr); exit(1)
        }
        canvas.mouseDown(with: event(.leftMouseDown, at: start))
        canvas.mouseDragged(with: event(.leftMouseDragged, at: firstHover))
        _ = canvas.frameForAccessibility(target.id)
        canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        canvas.mouseUp(with: event(.leftMouseUp, at: firstHover))
        guard model.roots == original, changes == 1 else {
            fputs("Escape must discard a latched candidate before release\n", stderr); exit(1)
        }
        window.orderOut(nil)
        print("painted-target follow, far-blank and Escape cancellation passed (offscreen only)")
    }
}
