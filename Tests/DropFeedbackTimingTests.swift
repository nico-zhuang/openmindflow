import AppKit

@main enum DropFeedbackTimingTests {
    static func main() {
        _ = NSApplication.shared // Detached canvas; no activation, HID, or user-window access.
        let suite = "snap-cue-timing-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        assert(L10n.setLanguage("zh-Hans", defaults: defaults))
        let target = MapNode(id: UUID(), title: "附加目标", children: [], folded: false)
        let second = MapNode(id: UUID(), title: "另一目标", children: [], folded: false)
        let source = MapNode(id: UUID(), title: "移动节点", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "主节点", children: [target, second, source], folded: false)
        let model = MapModel(roots: [root], selected: source.id)
        let canvas = MapCanvas(model: model)
        canvas.localizationDefaults = defaults
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        func center(_ box: CGRect) -> CGPoint { CGPoint(x: box.midX, y: box.midY) }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let sourcePoint = center(canvas.frameForAccessibility(source.id)!)
        let targetBox = canvas.frameForAccessibility(target.id)!
        let targetPoint = center(targetBox)
        let original = model.roots
        func targetPixels() -> [NSColor] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            canvas.displayIgnoringOpacity(canvas.bounds, in: context)
            NSGraphicsContext.restoreGraphicsState()
            return stride(from: Int(targetBox.minX + 16), through: Int(targetBox.maxX - 16), by: 3).flatMap { x in
                stride(from: Int(targetBox.minY + 9), through: Int(targetBox.maxY - 11), by: 3).compactMap {
                    bitmap.colorAt(x: x, y: $0)
                }
            }
        }
        let readableBefore = targetPixels()
        canvas.mouseDown(with: mouse(.leftMouseDown, sourcePoint))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, targetPoint))
        let began = ProcessInfo.processInfo.systemUptime
        assert(canvas.dropFeedback(now: began) == nil,
               "A valid attachment must not immediately flash its outline or text")
        assert(targetPixels() == readableBefore,
               "During the quiet delay, the held card must not bleed through the target title")
        assert(canvas.dropFeedback(now: began + 0.16) == nil,
               "The cue remains quiet during the brief dwell delay")
        guard let entering = canvas.dropFeedback(now: began + 0.24) else {
            fatalError("A stable destination gradually reveals the attachment cue")
        }
        assert(entering.targetID == target.id && entering.label == "附加" &&
               entering.opacity > 0 && entering.opacity < 0.8,
               "The outline and small Attach cue fade in instead of appearing at full strength")
        guard let full = canvas.dropFeedback(now: began + 0.45), let pill = full.badge else {
            fatalError("The steady Attach hint remains visible near the target")
        }
        assert(full.opacity >= 0.99 && pill.height <= 24 && pill.width < 56,
               "The new pill must be meaningfully smaller than the prior 32pt/56pt version")
        assert(canvas.frameForAccessibility(target.id)! == targetBox && model.roots == original,
               "Delaying the cue must not delay the actual drag or repel any node")
        let far = CGPoint(x: 1080, y: 640)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, far))
        assert((canvas.dropFeedback(now: began + 0.45)?.opacity ?? 0) > 0.9)
        let clearFadePixels = targetPixels() // Same translucent backing, source far away.
        let edge = CGPoint(x: targetBox.midX, y: targetBox.minY + 3)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, edge))
        assert((canvas.dropFeedback(now: began + 0.45)?.opacity ?? 0) > 0.9)
        assert(targetPixels() == clearFadePixels,
               "A held card crossing a fading target must not show its text beneath the target")
        canvas.mouseDragged(with: mouse(.leftMouseDragged, far))
        let departing = canvas.dropFeedback(now: began + 0.45)
        assert(departing?.targetID == target.id && departing!.opacity > 0.9,
               "Leaving the target begins a fade-out from the current presentation value")
        let fading = canvas.dropFeedback(now: began + 0.51)
        assert(fading?.opacity ?? 0 < departing!.opacity && (fading?.opacity ?? 0) > 0,
               "The previous cue fades down over multiple frames rather than vanishing abruptly")
        canvas.mouseDragged(with: mouse(.leftMouseDragged, targetPoint))
        let reversed = canvas.dropFeedback(now: began + 0.52)
        assert((reversed?.opacity ?? 0) > (fading?.opacity ?? 0) * 0.5,
               "Reentering the same target continues the ongoing fade curve, never flashing fully off")
        let recovering = canvas.dropFeedback(now: began + 0.61)
        assert((recovering?.opacity ?? 0) > (reversed?.opacity ?? 0),
               "Reversal should brighten continuously, without a new 180ms black gap")
        canvas.mouseDragged(with: mouse(.leftMouseDragged, far))
        assert(canvas.dropFeedback(now: began + 0.62) != nil)
        assert(canvas.dropFeedback(now: began + 0.76) == nil,
               "After the second fade-out the target has no leftover badge or halo")
        let gap = CGPoint(x: targetBox.midX, y: targetBox.minY + 3)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, gap))
        assert(canvas.dropFeedback(now: began + 0.77) == nil &&
               canvas.dropFeedback(now: began + 1.15) == nil,
               "Even after dwelling in a valid sibling insertion zone, no Insert cue appears")
        canvas.mouseDragged(with: mouse(.leftMouseDragged, targetPoint))
        assert(canvas.dropFeedback(now: began + 1.16) == nil,
               "Returning after a fully cleared cue restarts dwell instead of reusing stale opacity")
        assert(canvas.dropFeedback(now: began + 1.54)?.label == "附加")
        canvas.mouseUp(with: mouse(.leftMouseUp, targetPoint))
        assert(canvas.dropFeedback(now: began + 1.55) == nil,
               "Committing a move removes transient feedback immediately")
        do {
            let preceding = MapNode(id: UUID(), title: "Before", children: [], folded: false)
            let movedTarget = MapNode(id: UUID(), title: "Moved target", children: [], folded: false)
            let held = MapNode(id: UUID(), title: "Held", children: [], folded: false)
            let branch = MapNode(id: UUID(), title: "Root", children: [preceding, movedTarget, held], folded: false)
            let replay = MapCanvas(model: MapModel(roots: [branch], selected: held.id))
            replay.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
            var clock: TimeInterval = 200
            replay.cueClock = { clock }
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type,
                    location: CGPoint(x: point.x, y: replay.bounds.height - point.y),
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            let targetBefore = replay.frameForAccessibility(movedTarget.id)!
            replay.mouseDown(with: event(.leftMouseDown, center(replay.frameForAccessibility(held.id)!)))
            replay.mouseDragged(with: event(.leftMouseDragged, center(targetBefore)))
            assert(replay.dropFeedback() == nil)
            clock += 0.45
            assert(replay.dropFeedback()?.targetID == movedTarget.id)
            let firstBox = replay.frameForAccessibility(preceding.id)!
            replay.mouseDragged(with: event(.leftMouseDragged,
                CGPoint(x: firstBox.midX, y: firstBox.minY + 3)))
            guard let fading = replay.dropFeedback() else {
                fatalError("A stable attachment halo should begin fading on insertion hover")
            }
            let targetAfter = replay.frameForAccessibility(movedTarget.id)!
            assert(targetAfter != targetBefore, "Fixture must actually reflow the previous target")
            assert(fading.targetID == movedTarget.id &&
                   abs(fading.outline.midX - targetAfter.midX) < 1 &&
                   abs(fading.outline.midY - targetAfter.midY) < 1,
                   "A fading halo stays on its actual reflowing destination, not stale screen coordinates")
            replay.mouseUp(with: event(.leftMouseUp, CGPoint(x: firstBox.midX, y: firstBox.minY + 3)))
        }
        print("only Attach; delayed, smaller, weak fade-in/out; no lingering Insert or stale cue")
    }
}
