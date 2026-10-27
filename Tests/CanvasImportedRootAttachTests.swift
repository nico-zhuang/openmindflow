import AppKit

@main enum CanvasImportedRootAttachTests {
    static func main() {
        _ = NSApplication.shared // Detached imported-style model, never open a user's source.
        let target = MapNode(id: UUID(), title: "Target child", children: [], folded: false,
                             location: SIMD2(410, 210))
        let base = MapNode(id: UUID(), title: "Main", children: [target], folded: false,
                           location: SIMD2(160, 210))
        let formerChild = MapNode(id: UUID(), title: "Former child", children: [], folded: false,
                                  location: SIMD2(1120, 430))
        let importedRoot = MapNode(id: UUID(), title: "Imported root", children: [formerChild], folded: false,
                                   location: SIMD2(900, 430))
        let model = MapModel(roots: [base, importedRoot], selected: importedRoot.id)
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 1500, height: 850)
        func presentation(_ center: CGPoint) -> MindNodePresentation {
            MindNodePresentation(location: center, maxWidth: nil, allowToShrinkWidth: true,
                                 font: nil, styleChangedByUser: false, fillColor: nil)
        }
        canvas.nativePresentation = [base.id: presentation(CGPoint(x: 160, y: 210)),
                                     target.id: presentation(CGPoint(x: 410, y: 210)),
                                     importedRoot.id: presentation(CGPoint(x: 900, y: 430)),
                                     formerChild.id: presentation(CGPoint(x: 1120, y: 430))]
        let before = model.roots
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type,
                location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let start = canvas.frameForAccessibility(importedRoot.id)!
        let destination = canvas.frameForAccessibility(target.id)!
        let grab = CGPoint(x: start.midX, y: start.midY)
        let hover = CGPoint(x: destination.midX, y: destination.midY)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: grab))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: hover))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: hover))
        assert(model.roots.count == 1 && model.roots[0].children[0].children.map(\.id) == [importedRoot.id])
        let targetAfter = canvas.frameForAccessibility(target.id)!
        let moved = canvas.frameForAccessibility(importedRoot.id)!
        let descendant = canvas.frameForAccessibility(formerChild.id)!
        assert(moved.minX >= targetAfter.maxX + 40 &&
               descendant.minX >= moved.maxX + 40 &&
               abs(moved.midY - targetAfter.midY) < 60 &&
               abs(descendant.midY - moved.midY) < 60,
               "The whole imported subtree must use readable attached-branch positions beside the destination")
        assert(abs(moved.midX - start.midX) > 80 &&
               abs(descendant.midX - (1120 + 80)) > 80 &&
               !moved.intersects(targetAfter),
               "Neither imported node may remain pinned to its immutable original center")
        canvas.undo()
        assert(model.roots == before && canvas.frameForAccessibility(importedRoot.id)! == start,
               "Undo restores the imported root's original presentation without writing its source")
        print("imported root attach discards stale presentation location but Undo restores original")
    }
}
