import AppKit

@main enum LeftBranchInteractionTests {
    static func main() {
        _ = NSApplication.shared // Detached canvas only; no window, post or global HID.
        if CommandLine.arguments.contains("--model") { modelResizeTests(); return }
        if CommandLine.arguments.contains("--drag") { dragSwitchTests(); return }
        let defaults = UserDefaults(suiteName: "LeftBranchInteractionTests.\(UUID())")!
        defaults.set("en", forKey: "language")
        let leaf = MapNode(id: UUID(), title: "leaf", children: [], folded: false,
                           location: SIMD2(620, 310), note: "keep note")
        let child = MapNode(id: UUID(), title: "branch", children: [leaf], folded: false,
                            location: SIMD2(420, 310))
        let root = MapNode(id: UUID(), title: "root", children: [child], folded: false,
                           location: SIMD2(170, 310))
        let model = MapModel(roots: [root], selected: child.id)
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 750)
        canvas.localizationDefaults = defaults
        var changes = 0
        canvas.onChange = { changes += 1 }
        func fail(_ message: String) -> Never { fputs("RED: \(message)\n", stderr); exit(1) }
        func box(_ id: UUID) -> CGRect { canvas.frameForAccessibility(id)! }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func drag(_ from: CGPoint, _ to: CGPoint) {
            canvas.mouseDown(with: event(.leftMouseDown, from))
            canvas.mouseDragged(with: event(.leftMouseDragged, to))
            canvas.mouseUp(with: event(.leftMouseUp, to))
        }
        let rightMenu = canvas.contextMenu(for: child.id)
        guard let leftAction = rightMenu.item(withTitle: "Place on Left"),
              let rightAction = rightMenu.item(withTitle: "Place on Right"),
              leftAction.state == .off, rightAction.state == .on,
              canvas.contextMenu(for: root.id).item(withTitle: "Place on Left") == nil,
              canvas.contextMenu(for: leaf.id).item(withTitle: "Place on Left") == nil else {
            fail("only depth-one branch offers separate checked direction actions")
        }
        _ = canvas.contextMenu(for: child.id) // Root/deep menu probes changed selection.
        guard NSApp.sendAction(leftAction.action!, to: leftAction.target, from: leftAction),
              model.roots[0].children[0].branchSide == "left", changes == 1,
              model.roots[0].children[0].children[0].note == "keep note",
              model.roots[0].children[0].location == nil,
              model.roots[0].children[0].children[0].location == nil else {
            fail("context action changes the whole branch exactly once")
        }
        guard canvas.contextMenu(for: child.id).item(withTitle: "Place on Left")?.state == .on else {
            fail("context checkmark follows selected side")
        }
        _ = NSApp.sendAction(leftAction.action!, to: leftAction.target, from: leftAction)
        guard changes == 1, model.undo(), model.roots == [root], !model.undo(),
              model.redo(), model.roots[0].children[0].branchSide == "left" else {
            fail("repeated side action is no-op; one undo and redo")
        }
        let fromLeft = box(child.id)
        let leftEnd = CGPoint(x: box(root.id).maxX + 110, y: fromLeft.midY)
        drag(CGPoint(x: fromLeft.midX, y: fromLeft.midY), leftEnd)
        guard model.roots[0].children[0].branchSide == "right", changes == 2,
              model.roots[0].children[0].children[0].note == "keep note",
              model.roots[0].children[0].children[0].id == leaf.id,
              model.undo(), model.roots[0].children[0].branchSide == "left" else {
            fail("local event drag across root changes side, preserves subtree, one undo (side=\(String(describing: model.roots[0].children[0].branchSide)) changes=\(changes))")
        }
        assert(model.redo())
        let fromRight = box(child.id)
        drag(CGPoint(x: fromRight.midX, y: fromRight.midY),
             CGPoint(x: box(root.id).minX - 110, y: fromRight.midY))
        guard model.roots[0].children[0].branchSide == "left", changes == 3 else {
            fail("reverse local drag switches back to left")
        }
        // A left branch has an exterior resize hit, leftwards growth and a fixed right edge.
        let old = box(child.id)
        let handle = CGPoint(x: old.minX + 6, y: old.minY + 5)
        let farther = CGPoint(x: handle.x - 60, y: handle.y)
        canvas.mouseDown(with: event(.leftMouseDown, handle))
        canvas.mouseDragged(with: event(.leftMouseDragged, farther))
        let preview = box(child.id)
        guard preview.width > old.width + 50, abs(preview.maxX - old.maxX) < 2,
              model.roots[0].children[0].width == nil else {
            fail("left handle precommit preview grows outwards without model mutation")
        }
        canvas.mouseUp(with: event(.leftMouseUp, farther))
        let committed = box(child.id)
        guard committed.width > old.width + 50, abs(committed.maxX - old.maxX) < 2,
              changes == 4, model.undo(), model.roots[0].children[0].width == nil else {
            fail("left resize commits with right edge anchored and one undo (old=\(old), committed=\(committed), root=\(box(root.id)), changes=\(changes), width=\(String(describing: model.roots[0].children[0].width)))")
        }
        let zh = UserDefaults(suiteName: "LeftBranchInteractionTests.zh.\(UUID())")!
        zh.set("zh-Hans", forKey: "language")
        canvas.localizationDefaults = zh
        guard L10n.text("Place on Left", defaults: zh) == "放置在左侧",
              L10n.text("Place on Right", defaults: zh) == "放置在右侧",
              L10n.text("Left", defaults: zh) == "左对齐",
              canvas.contextMenu(for: child.id).item(withTitle: "放置在左侧") != nil else {
            fail("direction labels translated independently of alignment")
        }
        let imported = MapNode(id: UUID(), title: "imported left", children: [], folded: false)
        let importedRoot = MapNode(id: UUID(), title: "import root", children: [imported], folded: false)
        let importedModel = MapModel(roots: [importedRoot], selected: imported.id)
        let importedCanvas = MapCanvas(model: importedModel)
        importedCanvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 750)
        importedCanvas.nativePresentation[importedRoot.id] = MindNodePresentation(
            location: CGPoint(x: 650, y: 320), maxWidth: nil, allowToShrinkWidth: true,
            font: nil, styleChangedByUser: nil, fillColor: nil)
        importedCanvas.nativePresentation[imported.id] = MindNodePresentation(
            location: CGPoint(x: 320, y: 320), maxWidth: nil, allowToShrinkWidth: true,
            font: nil, styleChangedByUser: nil, fillColor: nil)
        let original = importedCanvas.frameForAccessibility(imported.id)!
        let importedHandle = CGPoint(x: original.minX + 6, y: original.minY + 5)
        func importedEvent(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type,
                location: CGPoint(x: point.x, y: importedCanvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        importedCanvas.mouseDown(with: importedEvent(.leftMouseDown, importedHandle))
        importedCanvas.mouseDragged(with: importedEvent(.leftMouseDragged,
            CGPoint(x: importedHandle.x - 40, y: importedHandle.y)))
        let importedPreview = importedCanvas.frameForAccessibility(imported.id)!
        guard importedPreview.width > original.width + 30,
              abs(importedPreview.maxX - original.maxX) < 2,
              importedModel.roots == [importedRoot] else {
            fail("nil-side actual-left import hit and preview use its rendered orientation")
        }
        importedCanvas.mouseUp(with: importedEvent(.leftMouseUp,
            CGPoint(x: importedHandle.x - 40, y: importedHandle.y)))
        guard abs(importedCanvas.frameForAccessibility(imported.id)!.maxX - original.maxX) < 2,
              importedModel.roots[0].children[0].branchSide == nil,
              importedModel.undo(), importedModel.roots == [importedRoot] else {
            fail("imported nil-side left resize preserves anchor, side and undo")
        }
        print("side menu, localized checks, local drag, left resize preview/import and undo passed")
    }

    private static func dragSwitchTests() {
        let grandchild = MapNode(id: UUID(), title: "grandchild", children: [], folded: false, note: "retained")
        let child = MapNode(id: UUID(), title: "child", children: [grandchild], folded: false)
        let root = MapNode(id: UUID(), title: "root", children: [child], folded: false)
        let model = MapModel(roots: [root], selected: child.id)
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 750)
        var changes = 0
        canvas.onChange = { changes += 1 }
        func center(_ id: UUID) -> CGPoint { canvas.frameForAccessibility(id)!.center }
        func send(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func drag(_ start: CGPoint, _ end: CGPoint) {
            let before = model.roots
            canvas.mouseDown(with: send(.leftMouseDown, start))
            canvas.mouseDragged(with: send(.leftMouseDragged, end))
            assert(model.roots == before, "drag preview must not edit model")
            canvas.mouseUp(with: send(.leftMouseUp, end))
        }
        let start = center(child.id)
        drag(start, CGPoint(x: center(root.id).x - 125, y: start.y))
        guard model.roots[0].children[0].branchSide == "left", changes == 1,
              model.roots[0].children[0].children[0].note == "retained",
              model.undo(), model.roots == [root], !model.undo(), model.redo() else {
            fputs("RED: local root child drag across center must switch side with one undo\n", stderr); exit(1)
        }
        let back = center(child.id)
        drag(back, CGPoint(x: center(root.id).x + 150, y: back.y))
        guard model.roots[0].children[0].branchSide == "right", changes == 2 else {
            fputs("RED: reverse local drag must restore right side\n", stderr); exit(1)
        }
        print("local root branch drag side switch passed")
    }

    private static func modelResizeTests() {
        let leaf = MapNode(id: UUID(), title: "leaf", children: [], folded: false,
                           location: SIMD2(-490, 100))
        var left = MapNode(id: UUID(), title: "left", children: [leaf], folded: false,
                           width: 170, location: SIMD2(-300, 100))
        left.branchSide = "left"
        var right = MapNode(id: UUID(), title: "right", children: [], folded: false,
                            width: 170, location: SIMD2(300, 100))
        right.branchSide = "right"
        let root = MapNode(id: UUID(), title: "root", children: [left, right], folded: false,
                           location: SIMD2(0, 100))
        let model = MapModel(roots: [root], selected: left.id)
        guard !model.resizeSelected(by: .nan, visibleWidths: [left.id: 170]),
              !model.resizeSelected(by: .infinity, visibleWidths: [left.id: 170]),
              !model.resizeSelected(by: 10, visibleWidths: [:]),
              !model.undo() else { fatalError("Invalid resize creates history") }
        guard model.resizeSelected(by: 60, visibleWidths: [left.id: 170]),
              model.roots[0].children[0].width == 230,
              model.roots[0].children[0].location == SIMD2(-330, 100),
              model.roots[0].children[0].children[0].location == SIMD2(-550, 100),
              model.undo(), model.roots == [root], !model.undo() else {
            fputs("RED: widening left branch shifts own center half left, descendants full left with one undo\n", stderr); exit(1)
        }
        guard model.setWidth(230, anchoredFrom: 170),
              model.roots[0].children[0].location == SIMD2(-330, 100),
              model.undo(), model.roots == [root] else {
            fputs("RED: left setWidth keeps right edge anchored and undo\n", stderr); exit(1)
        }
        assert(model.toggleSelection(right.id))
        guard model.resizeSelected(by: 40, visibleWidths: [left.id: 170, right.id: 170]),
              model.roots[0].children[0].location == SIMD2(-320, 100),
              model.roots[0].children[0].children[0].location == SIMD2(-530, 100),
              model.roots[0].children[1].location == SIMD2(320, 100),
              model.undo(), model.roots == [root] else {
            fputs("RED: mixed multi selection anchors each side independently\n", stderr); exit(1)
        }
        print("model left/right width anchors, descendants, mixed selection and undo passed")
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
