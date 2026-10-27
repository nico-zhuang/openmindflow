import AppKit

private final class SimulatedPresentedWindow: NSWindow {
    var simulatedVisible = true
    override var isVisible: Bool { simulatedVisible }
}

@main enum DropFeedbackTimerLifecycleTests {
    static func main() {
        _ = NSApplication.shared
        let target = MapNode(id: UUID(), title: "Target", children: [], folded: false)
        let source = MapNode(id: UUID(), title: "Held", children: [], folded: false)
        let model = MapModel(roots: [MapNode(id: UUID(), title: "Main", children: [target, source], folded: false)],
                             selected: source.id)
        let canvas = MapCanvas(model: model)
        let window = SimulatedPresentedWindow(contentRect: CGRect(x: 100, y: 100, width: 1100, height: 700),
                                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas // Never order the window or take user focus.
        let frames = Dictionary(uniqueKeysWithValues: mapLayout(model.roots).map { ($0.node.id, $0.frame) })
        func mouse(_ type: NSEvent.EventType, _ id: UUID) -> NSEvent {
            let frame = frames[id]!
            let local = CGPoint(x: frame.midX + 80, y: canvas.bounds.height - frame.midY - 90)
            return NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, source.id))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, target.id))
        assert(canvas.dropFeedback() == nil)
        let reflected = Mirror(reflecting: canvas).children.first { $0.label == "cueTimer" }?.value
        guard let timer = reflected.flatMap({ Mirror(reflecting: $0).children.first?.value as? Timer }),
              timer.isValid else { fatalError("A presented window must schedule cue opacity frames") }
        assert(!window.isKeyWindow && !window.isMainWindow,
               "Simulated visibility must never activate or show a user-facing window")
        canvas.needsDisplay = false
        timer.fire()
        assert(canvas.needsDisplay,
               "The native timer must request the next opacity frame while the window is presented")
        window.simulatedVisible = false
        timer.fire() // Invoke its own callback without sleeping or pumping any user's event loop.
        assert(!timer.isValid, "Hidden windows must stop the 60-Hz animation timer even without another draw")
        window.simulatedVisible = true
        assert(canvas.dropFeedback() == nil)
        let resumed = Mirror(reflecting: canvas).children.first { $0.label == "cueTimer" }?.value
        guard let detachingTimer = resumed.flatMap({ Mirror(reflecting: $0).children.first?.value as? Timer }),
              detachingTimer.isValid else { fatalError("Resumed hover should schedule a fresh timer") }
        window.contentView = NSView(frame: window.contentView!.bounds)
        assert(!detachingTimer.isValid, "Detaching a canvas must stop its active timer without a further tick")
        window.orderOut(nil)
        print("synthetic no-focus timer schedules then stops after hide/detach")
    }
}
