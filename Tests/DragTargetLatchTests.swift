import AppKit

@main
enum DragTargetLatchTests {
    static func main() {
        _ = NSApplication.shared
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            print("drag target latch test skipped: Reduce Motion is enabled")
            return
        }
        do {
            let collision = MapNode(id: UUID(), title: "Colliding third branch", children: [], folded: false)
            var pinned = MapNode(id: UUID(), title: "Pinned wide target", children: [], folded: false)
            pinned.width = 480
            let source = MapNode(id: UUID(), title: "Dragged narrow source", children: [], folded: false)
            let placeholder = MapNode(id: UUID(), title: "Root", children: [collision, pinned, source], folded: false)
            let baseline = mapLayout([placeholder])
            let pinnedBox = baseline.first { $0.node.id == pinned.id }!.frame
            let sourceBox = baseline.first { $0.node.id == source.id }!.frame
            var nearby = collision
            nearby.location = SIMD2(Double(pinnedBox.maxX - 85), Double(pinnedBox.midY - 30))
            let map = MapModel(roots: [MapNode(id: placeholder.id, title: "Root",
                                            children: [nearby, pinned, source], folded: false)], selected: source.id)
            let view = MapCanvas(model: map)
            let offscreen = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 700),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
            offscreen.contentView = view // Never shown or made key.
            let pinnedBefore = view.frameForAccessibility(pinned.id)!
            let nearbyBefore = view.frameForAccessibility(nearby.id)!
            func mouse(_ kind: NSEvent.EventType, _ world: CGPoint) -> NSEvent {
                let point = CGPoint(x: world.x + 80, y: view.bounds.height - world.y - 90)
                return NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: sourceBox.midX, y: sourceBox.midY)))
            view.mouseDragged(with: mouse(.leftMouseDragged,
                CGPoint(x: sourceBox.midX, y: pinnedBox.minY + 5)))
            let pinnedAfter = view.frameForAccessibility(pinned.id)!
            let nearbyAfter = view.frameForAccessibility(nearby.id)!
            guard pinnedAfter == pinnedBefore, nearbyAfter == nearbyBefore,
                  map.roots[0].children.count == 3 else {
                fputs("Dragging must not shove the visible target or adjacent node: target \(pinnedBefore) -> \(pinnedAfter), neighbor \(nearbyBefore) -> \(nearbyAfter)\n", stderr); exit(1)
            }
            view.advanceSpring(at: ProcessInfo.processInfo.systemUptime + 0.12)
            guard view.frameForAccessibility(pinned.id)! == pinnedBefore,
                  view.frameForAccessibility(nearby.id)! == nearbyBefore else {
                fputs("Neither target nor neighbor should move under a stationary pointer\n", stderr); exit(1)
            }
            view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: sourceBox.midX, y: pinnedBox.minY + 5)))
            offscreen.orderOut(nil)
        }
        do {
            let source = MapNode(id: UUID(), title: "Source", children: [], folded: false)
            let neighbor = MapNode(id: UUID(), title: "Static neighbor", children: [], folded: false)
            let root = MapNode(id: UUID(), title: "Root", children: [source, neighbor], folded: false)
            let map = MapModel(roots: [root], selected: source.id)
            let view = MapCanvas(model: map)
            view.frame = CGRect(x: 0, y: 0, width: 1100, height: 700)
            let frames = Dictionary(uniqueKeysWithValues: mapLayout(map.roots).map { ($0.node.id, $0.frame) })
            let before = view.frameForAccessibility(neighbor.id)!
            func event(_ kind: NSEvent.EventType, _ world: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: kind,
                    location: CGPoint(x: world.x + 80, y: view.bounds.height - world.y - 90),
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            let start = CGPoint(x: frames[source.id]!.midX, y: frames[source.id]!.midY)
            let nearEdge = CGPoint(x: frames[neighbor.id]!.minX - 3, y: frames[neighbor.id]!.midY)
            view.mouseDown(with: event(.leftMouseDown, start))
            view.mouseDragged(with: event(.leftMouseDragged, nearEdge))
            guard view.frameForAccessibility(neighbor.id)! == before else {
                fputs("Invalid hover must not repel an adjacent node\n", stderr); exit(1)
            }
            view.mouseUp(with: event(.leftMouseUp, nearEdge))
            guard map.roots == [root] && view.frameForAccessibility(neighbor.id)! == before else {
                fputs("Invalid neighboring drop must not move or reparent anything\n", stderr); exit(1)
            }
        }
        do {
            let b = MapNode(id: UUID(), title: "B", children: [], folded: false)
            let s = MapNode(id: UUID(), title: "Source", children: [], folded: false)
            let firstRoot = MapNode(id: UUID(), title: "First root", children: [b, s], folded: false)
            let baseline = mapLayout([firstRoot])
            let bBox = baseline.first { $0.node.id == b.id }!.frame
            let sBox = baseline.first { $0.node.id == s.id }!.frame
            let a = MapNode(id: UUID(), title: "Topmost A", children: [], folded: false,
                            location: SIMD2(Double(bBox.midX), Double(bBox.midY + 30)))
            let overlapMap = MapModel(roots: [firstRoot, a], selected: s.id)
            let overlapCanvas = MapCanvas(model: overlapMap)
            overlapCanvas.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x + 80, y: overlapCanvas.bounds.height - y - 90)
            }
            func overlapEvent(_ kind: NSEvent.EventType, _ position: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: kind, location: position, modifierFlags: [], timestamp: 0,
                                   windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            overlapCanvas.mouseDown(with: overlapEvent(.leftMouseDown, point(sBox.midX, sBox.midY)))
            overlapCanvas.mouseDragged(with: overlapEvent(.leftMouseDragged, point(bBox.midX, bBox.midY - 10)))
            _ = overlapCanvas.frameForAccessibility(b.id)
            let overlap = point(bBox.midX, bBox.midY + 17)
            overlapCanvas.mouseDragged(with: overlapEvent(.leftMouseDragged, overlap))
            _ = overlapCanvas.frameForAccessibility(a.id)
            overlapCanvas.mouseUp(with: overlapEvent(.leftMouseUp, overlap))
            guard overlapMap.roots[1].children.map(\.id) == [s.id],
                  overlapMap.roots[0].children.map(\.id) == [b.id] else {
                fputs("Topmost genuine target must supersede old overlapping target\n", stderr); exit(1)
            }
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
        let originalTargetAX = canvas.frameForAccessibility(target.id)!
        let originalRootAX = canvas.frameForAccessibility(root.id)!
        canvas.advanceSpring(at: ProcessInfo.processInfo.systemUptime + 0.12)
        guard abs(canvas.frameForAccessibility(root.id)!.midY - originalRootAX.midY) > 1 else {
            fputs("Pinning a drop target must not suppress other branches' preview spring\n", stderr); exit(1)
        }
        guard abs(canvas.frameForAccessibility(target.id)!.midY - originalTargetAX.midY) < 0.5 else {
            fputs("Stationary pointer must keep its initially visible drop target stationary during preview\n", stderr); exit(1)
        }
        for step in 1...8 {
            canvas.advanceSpring(at: ProcessInfo.processInfo.systemUptime + 0.12 + Double(step) * 0.03)
            guard abs(paintedCenter().y - firstHover.y) < 0.5 else {
                fputs("Stationary cursor's drop target must not drift during dwell\n", stderr); exit(1)
            }
        }
        canvas.mouseUp(with: event(.leftMouseUp, at: firstHover))
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
        func checkSameTarget(startFraction: CGFloat, endFraction: CGFloat,
                             destination: [Int], child: Bool, label: String) {
            let t = MapNode(id: UUID(), title: "Target", children: [], folded: false)
            let middle = MapNode(id: UUID(), title: "Middle", children: [], folded: false)
            let s = MapNode(id: UUID(), title: "Source", children: [], folded: false)
            let map = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [t, middle, s], folded: false)],
                               selected: s.id)
            let view = MapCanvas(model: map)
            view.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
            let layout = mapLayout(map.roots)
            let sourceBox = layout.first { $0.node.id == s.id }!.frame
            let targetBox = layout.first { $0.node.id == t.id }!.frame
            func hover(_ fraction: CGFloat) -> CGPoint {
                CGPoint(x: targetBox.midX + 80,
                        y: view.bounds.height - targetBox.minY - targetBox.height * fraction - 90)
            }
            let grab = CGPoint(x: sourceBox.midX + 80, y: view.bounds.height - sourceBox.midY - 90)
            view.mouseDown(with: event(.leftMouseDown, at: grab))
            view.mouseDragged(with: event(.leftMouseDragged, at: hover(startFraction)))
            _ = view.frameForAccessibility(t.id)
            view.mouseDragged(with: event(.leftMouseDragged, at: hover(endFraction)))
            _ = view.frameForAccessibility(t.id)
            view.mouseUp(with: event(.leftMouseUp, at: hover(endFraction)))
            let ids = [t.id, middle.id, s.id]
            guard map.roots[0].children.map(\.id) == destination.map({ ids[$0] }),
                  (map.roots[0].children.first(where: { $0.id == t.id })?.children.map(\.id) == [s.id]) == child else {
                fputs("Same painted target must update \(label) placement across real drop zones\n", stderr); exit(1)
            }
        }
        checkSameTarget(startFraction: 0.5, endFraction: 0.2,
                        destination: [2, 0, 1], child: false, label: "child-to-sibling")
        checkSameTarget(startFraction: 0.1, endFraction: 0.5,
                        destination: [0, 1], child: true, label: "sibling-to-child")
        checkSameTarget(startFraction: 0.1, endFraction: 0.9,
                        destination: [0, 2, 1], child: false, label: "sibling-index")
        window.orderOut(nil)
        print("stationary target, three-branch pair sweep, overlap, cancellation and drop zones passed (offscreen only)")
    }
}
