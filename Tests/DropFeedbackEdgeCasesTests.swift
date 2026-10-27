import AppKit

@main enum DropFeedbackEdgeCasesTests {
    static func main() {
        _ = NSApplication.shared // Synthetic detached views; never interact with a user window.
        func canvas(_ roots: [MapNode], selected: UUID) -> MapCanvas {
            let view = MapCanvas(model: MapModel(roots: roots, selected: selected))
            view.frame = CGRect(x: 0, y: 0, width: 1400, height: 900)
            return view
        }
        func mouse(_ view: MapCanvas, _ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type,
                location: CGPoint(x: point.x, y: view.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func center(_ frame: CGRect) -> CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
        do {
            let moving = MapNode(id: UUID(), title: "Selected A", children: [], folded: false)
            let inner = MapNode(id: UUID(), title: "Unselected child C", children: [], folded: false)
            let selectedParent = MapNode(id: UUID(), title: "Selected B", children: [inner], folded: false)
            let root = MapNode(id: UUID(), title: "Main", children: [moving, selectedParent], folded: false)
            let view = canvas([root], selected: moving.id)
            assert(view.model.selectNodes([moving.id, selectedParent.id]))
            let original = view.model.roots
            let from = center(view.frameForAccessibility(moving.id)!)
            let to = center(view.frameForAccessibility(inner.id)!)
            view.mouseDown(with: mouse(view, .leftMouseDown, from))
            view.mouseDragged(with: mouse(view, .leftMouseDragged, to))
            assert(view.dropFeedback() == nil,
                   "An unselected descendant inside a selected moving subtree is not a stationary destination")
            view.mouseUp(with: mouse(view, .leftMouseUp, to))
            assert(view.model.roots == original,
                   "No false cue may promise a group attachment that moveSelectedNodes rejects")
        }
        do {
            let source = MapNode(id: UUID(), title: "Right branch", children: [], folded: false)
            let left = MapNode(id: UUID(), title: "Left target", children: [], folded: false,
                               branchSide: "left")
            let root = MapNode(id: UUID(), title: "Main", children: [source, left], folded: false)
            let view = canvas([root], selected: source.id)
            let from = center(view.frameForAccessibility(source.id)!)
            let to = center(view.frameForAccessibility(left.id)!)
            view.mouseDown(with: mouse(view, .leftMouseDown, from))
            view.mouseDragged(with: mouse(view, .leftMouseDragged, to))
            assert(view.dropFeedback() == nil,
                   "An opposite-side root-branch drag changes side on release; it must not falsely say Attach")
            view.mouseUp(with: mouse(view, .leftMouseUp, to))
            assert(view.model.roots[0].children.map(\.id) == [source.id, left.id] &&
                   view.model.roots[0].children[0].branchSide == "left",
                   "Suppressing a misleading cue must not change existing branch-side drop semantics")
        }
        do {
            let target = MapNode(id: UUID(), title: "Target", children: [], folded: false,
                                 location: SIMD2(520, 430))
            let dragged = MapNode(id: UUID(), title: "Dragged", children: [], folded: false,
                                  location: SIMD2(1060, 430))
            let main = MapNode(id: UUID(), title: "Main", children: [target, dragged], folded: false,
                               location: SIMD2(160, 430))
            let targetScreen = canvas([main], selected: dragged.id).frameForAccessibility(target.id)!
            let targetBox = targetScreen.offsetBy(dx: -80, dy: -90)
            let width: Double = 172, height: Double = 50
            let badgeWidth: Double = 68
            func blocker(_ title: String, _ x: Double, _ y: Double) -> MapNode {
                MapNode(id: UUID(), title: title, children: [], folded: false,
                        width: CGFloat(width), location: SIMD2(x, y))
            }
            let below = blocker("Below", Double(targetBox.midX), Double(targetBox.maxY) + 10 + 32 / 2 + height / 2)
            let above = blocker("Above", Double(targetBox.midX), Double(targetBox.minY) - 10 - 32 / 2 - height / 2)
            let right = blocker("Right", Double(targetBox.maxX) + 10 + badgeWidth / 2 + width / 2,
                                Double(targetBox.midY))
            let left = blocker("Left", Double(targetBox.minX) - 10 - badgeWidth / 2 - width / 2,
                               Double(targetBox.midY))
            let view = canvas([main, below, above, right, left], selected: dragged.id)
            let from = center(view.frameForAccessibility(dragged.id)!)
            let to = center(view.frameForAccessibility(target.id)!)
            view.mouseDown(with: mouse(view, .leftMouseDown, from))
            view.mouseDragged(with: mouse(view, .leftMouseDragged, to))
            guard let feedback = view.dropFeedback() else {
                fatalError("A valid central child attach still needs a nearby cue")
            }
            let fixed = [below, above, right, left].compactMap { view.frameForAccessibility($0.id) }
            guard let badge = feedback.badge else {
                fatalError("The larger canvas has free space beyond the four immediate blocked directions")
            }
            assert(feedback.kind == .attach && feedback.targetID == target.id &&
                   fixed.allSatisfy { !badge.intersects($0) } &&
                   view.bounds.contains(badge),
                   "Even when all four immediate directions are occupied, the label must find free space")
            view.mouseUp(with: mouse(view, .leftMouseUp, to))
        }
        print("no group descendant false target, no opposite-side false attach, crowded badge avoids nodes")
    }
}
