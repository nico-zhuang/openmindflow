import AppKit

@main enum LeftBranchCanvasTests {
    static func main() {
        _ = NSApplication.shared // Detached bitmap and local events only; never create a window.
        UserDefaults.standard.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        let parent = CGRect(x: 300, y: 80, width: 150, height: 60)
        let right = CGRect(x: 520, y: 100, width: 120, height: 50)
        let left = CGRect(x: 110, y: 110, width: 120, height: 50)
        let rightRoot = branchConnectorEndpoints(parent: parent, child: right,
            parentIsRoot: true, goesLeft: false, baselineInset: 7)
        assert(rightRoot.start == CGPoint(x: 450, y: 110) && rightRoot.end == CGPoint(x: 520, y: 143) && rightRoot.controlX == 485)
        let leftRoot = branchConnectorEndpoints(parent: parent, child: left,
            parentIsRoot: true, goesLeft: true, baselineInset: 7)
        assert(leftRoot.start == CGPoint(x: 300, y: 110) && leftRoot.end == CGPoint(x: 230, y: 153) && leftRoot.controlX == 265)
        let leftGrandchild = branchConnectorEndpoints(parent: left, child: CGRect(x: -70, y: 175, width: 110, height: 45),
            parentIsRoot: false, goesLeft: true, baselineInset: 7)
        assert(leftGrandchild.start == CGPoint(x: 110, y: 153) && leftGrandchild.end == CGPoint(x: 40, y: 213) && leftGrandchild.controlX == 75)
        let rightGrandchild = branchConnectorEndpoints(parent: right, child: CGRect(x: 710, y: 175, width: 110, height: 45),
            parentIsRoot: false, goesLeft: false, baselineInset: 7)
        assert(rightGrandchild.start == CGPoint(x: 640, y: 143) && rightGrandchild.end == CGPoint(x: 710, y: 213) && rightGrandchild.controlX == 675)

        var grandchild = MapNode(id: UUID(), title: "Left grandchild", children: [], folded: false)
        grandchild.note = "Grandchild note"
        var leftChild = MapNode(id: UUID(), title: "Left child", children: [grandchild], folded: false, branchSide: "left")
        leftChild.note = "Left note"
        var rightChild = MapNode(id: UUID(), title: "Right child", children: [], folded: false)
        rightChild.note = "Right note"
        let root = MapNode(id: UUID(), title: "Root", children: [leftChild, rightChild], folded: false)
        let model = MapModel(roots: [root], selected: root.id)
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 700)
        canvas.appearance = NSAppearance(named: .aqua)
        canvas.shiftViewport(by: CGPoint(x: 420, y: 0)) // Keep the left note inside the detached bitmap at zoom 1.
        let boxes = [root.id, leftChild.id, rightChild.id, grandchild.id].reduce(into: [UUID: CGRect]()) {
            $0[$1] = canvas.frameForAccessibility($1)!
        }
        let l = boxes[leftChild.id]!, r = boxes[rightChild.id]!, g = boxes[grandchild.id]!
        assert(l.maxX < boxes[root.id]!.minX && g.maxX < l.minX && r.minX > boxes[root.id]!.maxX)
        assert(canvas.plusFrameForAccessibility(leftChild.id)!.midX == l.minX - 15)
        assert(canvas.plusFrameForAccessibility(grandchild.id)!.midX == g.minX - 15)
        assert(canvas.plusFrameForAccessibility(rightChild.id)!.midX == r.maxX + 15)
        assert(canvas.plusFrameForAccessibility(root.id)!.midX == boxes[root.id]!.maxX + 15)

        func bitmap() -> NSBitmapImageRep {
            canvas.needsDisplay = true
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 700,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
            canvas.effectiveAppearance.performAsCurrentDrawingAppearance { canvas.draw(canvas.bounds) }
            NSGraphicsContext.current = previous
            return image
        }
        func changed(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in rect: CGRect) -> Bool {
            for x in Int(rect.minX)..<Int(rect.maxX) where x >= 0 && x < a.pixelsWide {
                for y in Int(rect.minY)..<Int(rect.maxY) where y >= 0 && y < a.pixelsHigh {
                    let first = a.colorAt(x: x, y: a.pixelsHigh - 1 - y)!.usingColorSpace(.deviceRGB)!
                    let second = b.colorAt(x: x, y: b.pixelsHigh - 1 - y)!.usingColorSpace(.deviceRGB)!
                    if abs(first.redComponent - second.redComponent) + abs(first.greenComponent - second.greenComponent) + abs(first.blueComponent - second.blueComponent) > 0.2 { return true }
                }
            }
            return false
        }
        let noted = bitmap()
        assert(model.setNote("", for: leftChild.id))
        let unnoted = bitmap()
        let leftPaper = CGRect(x: l.minX - 22, y: l.maxY - 34, width: 17, height: 29)
        assert(changed(noted, unnoted, in: leftPaper), "Left child note paper must be outside left edge: \(l)")
        assert(!changed(noted, unnoted, in: CGRect(x: l.maxX + 4, y: l.maxY - 34, width: 20, height: 29)),
               "Left note must not remain beyond right edge")
        assert(model.setNote("Left note", for: leftChild.id))
        func mouse(_ kind: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let plus = canvas.plusFrameForAccessibility(leftChild.id)!.center
        canvas.mouseMoved(with: mouse(.mouseMoved, plus))
        mapLayoutInvocations = 0
        canvas.resetCursorRects()
        assert(mapLayoutInvocations == 1, "Cursor plus geometry must reuse its single layout without mutating preview state")
        let button = canvas.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
            .first { $0.accessibilityLabel() == "Add Child" && abs($0.accessibilityFrame().midX - plus.x) < 0.1 }
        assert(button?.accessibilityFrame().midX == plus.x && button?.accessibilityFrame().midY == plus.y)
        canvas.mouseDown(with: mouse(.leftMouseDown, plus))
        canvas.mouseUp(with: mouse(.leftMouseUp, plus))
        assert(model.roots[0].children[0].children.count == 2, "Left plus hit adds child")

        // Imported nil side is inferred solely from the actual laid-out frames, never persisted.
        var imported = MapNode(id: UUID(), title: "Imported left", children: [], folded: false)
        imported.note = "Imported note"
        let importedRoot = MapNode(id: UUID(), title: "Imported root", children: [imported], folded: false)
        let importedModel = MapModel(roots: [importedRoot], selected: importedRoot.id)
        let importedCanvas = MapCanvas(model: importedModel)
        importedCanvas.frame = canvas.frame
        importedCanvas.nativePresentation[importedRoot.id] = MindNodePresentation(location: CGPoint(x: 640, y: 230),
            maxWidth: nil, allowToShrinkWidth: nil, font: nil, styleChangedByUser: nil, fillColor: nil)
        importedCanvas.nativePresentation[imported.id] = MindNodePresentation(location: CGPoint(x: 300, y: 230),
            maxWidth: nil, allowToShrinkWidth: nil, font: nil, styleChangedByUser: nil, fillColor: nil)
        let importedBox = importedCanvas.frameForAccessibility(imported.id)!
        assert(importedBox.maxX < importedCanvas.frameForAccessibility(importedRoot.id)!.minX)
        assert(importedCanvas.plusFrameForAccessibility(imported.id)!.midX == importedBox.minX - 15)
        assert(importedModel.roots[0].children[0].branchSide == nil && importedCanvas.nativePresentation[imported.id]?.location == CGPoint(x: 300, y: 230))
        print("left/right root and descendant connector endpoints, note ink, plus AX/hit and imported nil-side passed")
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
