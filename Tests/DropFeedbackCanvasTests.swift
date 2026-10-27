import AppKit

@main enum DropFeedbackCanvasTests {
    static func main() {
        _ = NSApplication.shared // Synthetic detached view; never activate or access an existing window.
        let suite = "openmindflow-drop-cue-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        assert(L10n.setLanguage("zh-Hans", defaults: defaults))
        let target = MapNode(id: UUID(), title: "目标节点", children: [], folded: false)
        let other = MapNode(id: UUID(), title: "相邻节点", children: [], folded: false)
        let source = MapNode(id: UUID(), title: "被拖节点", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "主节点", children: [target, other, source], folded: false)
        let model = MapModel(roots: [root], selected: source.id)
        let canvas = MapCanvas(model: model)
        canvas.localizationDefaults = defaults
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type,
                location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func center(_ box: CGRect) -> CGPoint { CGPoint(x: box.midX, y: box.midY) }
        func image() -> Data {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            canvas.displayIgnoringOpacity(canvas.bounds, in: context)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using: .png, properties: [:])!
        }
        let before = model.roots
        let start = center(canvas.frameForAccessibility(source.id)!)
        let targetBefore = canvas.frameForAccessibility(target.id)!
        let initialImage = image()
        assert(canvas.dropFeedback() == nil, "No snap outline or hint before the drag starts")
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: center(targetBefore)))
        guard let attach = canvas.dropFeedback() else {
            fatalError("A valid child hover needs a visible target halo and Attach cue")
        }
        assert(attach.targetID == target.id && attach.kind == .attach && attach.label == "附加",
               "Valid child drop highlights the actual destination and names the action")
        guard let attachBadge = attach.badge else { fatalError("Visible space permits an Attach pill") }
        assert(attach.outline.insetBy(dx: 5, dy: 5).intersects(targetBefore) &&
               canvas.bounds.contains(attachBadge) &&
               !attachBadge.intersects(canvas.frameForAccessibility(other.id)!),
               "The nearby pill must not cover a different node's text while highlighting the target")
        assert(canvas.frameForAccessibility(target.id)! == targetBefore && model.roots == before,
               "Showing the cue must not repel the hovered target or edit the document")
        let activeImage = image()
        assert(activeImage != initialImage, "The valid hover visibly renders the drag and its cue")
        if CommandLine.arguments.count > 1 {
            try? activeImage.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
        }
        assert(L10n.setLanguage("en", defaults: defaults))
        assert(canvas.dropFeedback()?.label == "Attach", "English cue follows the canvas language setting")
        assert(L10n.setLanguage("zh-Hans", defaults: defaults))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 1080, y: 640)))
        assert(canvas.dropFeedback() == nil, "An invalid blank hover clears outline and tip immediately")
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 1080, y: 640)))
        assert(model.roots == before && canvas.dropFeedback() == nil,
               "Releasing away from a child target makes no false attachment")

        let nearTop = CGPoint(x: targetBefore.midX, y: targetBefore.minY + 3)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: nearTop))
        guard let insert = canvas.dropFeedback() else {
            fatalError("A valid sibling hover needs its distinct Insert cue")
        }
        assert(insert.targetID == target.id && insert.kind == .insert && insert.label == "插入",
               "Sibling insertion zone must not falsely claim the node will attach as a child")
        assert(canvas.frameForAccessibility(target.id)! == targetBefore && model.roots == before)
        canvas.mouseUp(with: mouse(.leftMouseUp, at: nearTop))
        assert(model.roots[0].children.map(\.id) == [source.id, target.id, other.id] &&
               canvas.dropFeedback() == nil,
               "Commit uses the previewed insertion while the ephemeral pill disappears")
        model.undo()
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: center(targetBefore)))
        assert(canvas.dropFeedback() != nil)
        canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        canvas.mouseUp(with: mouse(.leftMouseUp, at: center(targetBefore)))
        assert(canvas.dropFeedback() == nil && model.roots == before,
               "Escape clears both target halo and text before mouse release")
        let windowTarget = MapNode(id: UUID(), title: "Window target", children: [], folded: false)
        let windowSource = MapNode(id: UUID(), title: "Window source", children: [], folded: false)
        let windowRoot = MapNode(id: UUID(), title: "Window main", children: [windowTarget, windowSource], folded: false)
        let windowModel = MapModel(roots: [windowRoot], selected: windowSource.id)
        let inWindow = MapCanvas(model: windowModel)
        let syntheticWindow = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1100, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        syntheticWindow.contentView = inWindow // Never shown, made key or activated.
        let positions = Dictionary(uniqueKeysWithValues: mapLayout(windowModel.roots).map { ($0.node.id, $0.frame) })
        func windowMouse(_ kind: NSEvent.EventType, _ frame: CGRect) -> NSEvent {
            let point = CGPoint(x: frame.midX + 80, y: inWindow.bounds.height - frame.midY - 90)
            return NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let unmoved = inWindow.frameForAccessibility(windowTarget.id)!
        inWindow.mouseDown(with: windowMouse(.leftMouseDown, positions[windowSource.id]!))
        inWindow.mouseDragged(with: windowMouse(.leftMouseDragged, positions[windowTarget.id]!))
        assert(inWindow.dropFeedback()?.targetID == windowTarget.id &&
               inWindow.frameForAccessibility(windowTarget.id)! == unmoved &&
               !syntheticWindow.isVisible && !syntheticWindow.isKeyWindow,
               "A real but unshown native NSWindow retains its destination cue without moving target or stealing focus")
        inWindow.mouseUp(with: windowMouse(.leftMouseUp, positions[windowTarget.id]!))
        syntheticWindow.orderOut(nil)
        print("attach/insert badges, stationary target ring, localization, native offscreen window, invalid hover and Escape passed")
    }
}
