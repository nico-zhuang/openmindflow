import AppKit

@main enum RelationshipCanvasTests {
    static func main() {
        _ = NSApplication.shared // Detached synthetic canvas; no window or event loop.
        let a = MapNode(id: UUID(), title: "Start", children: [], folded: false,
                        location: SIMD2(160, 180))
        let b = MapNode(id: UUID(), title: "Finish", children: [], folded: false,
                        location: SIMD2(610, 180))
        let model = MapModel(roots: [a, b], selected: a.id)
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        func label(_ english: String) -> String { L10n.text(english, defaults: canvas.localizationDefaults) }
        assert(model.toggleSelection(b.id))
        guard let create = canvas.contextMenu(for: a.id).item(withTitle: label("Create Relationship")) else {
            fputs("RED: Two selected nodes must offer Create Relationship\n", stderr); exit(1)
        }
        guard NSApp.sendAction(create.action!, to: create.target, from: create),
              model.relationships.count == 1, model.selectedIDs == [a.id, b.id] else {
            fputs("Relationship creation must retain both selected nodes\n", stderr); exit(1)
        }
        let id = model.relationships[0].id
        assert(canvas.selectedRelationshipID == id)
        let first = canvas.frameForAccessibility(a.id)!, second = canvas.frameForAccessibility(b.id)!
        let start = CGPoint(x: first.maxX, y: first.midY)
        let end = CGPoint(x: second.minX, y: second.midY)
        let middle = CGPoint(x: (start.x + end.x) / 2, y: start.y)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type,
                location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func action(_ item: NSMenuItem) { assert(NSApp.sendAction(item.action!, to: item.target, from: item)) }
        canvas.mouseDown(with: event(.leftMouseDown, middle))
        canvas.mouseUp(with: event(.leftMouseUp, middle))
        assert(canvas.selectedRelationshipID == id && model.selectedIDs == [a.id, b.id],
               "Selecting curve cannot also begin marquee or select a node")
        let menu = canvas.menu(for: event(.rightMouseDown, middle))!
        guard let style = menu.item(withTitle: label("Line Style"))?.submenu,
              let dotted = style.item(withTitle: label("Dotted")),
              let startArrow = menu.item(withTitle: label("Start Arrow")),
              let endArrow = menu.item(withTitle: label("End Arrow")),
              let remove = menu.item(withTitle: label("Delete Relationship")) else {
            fputs("RED: Curve right-click must expose style, both arrows and deletion\n", stderr); exit(1)
        }
        action(dotted)
        assert(model.relationships[0].style == .dotted)
        action(startArrow)
        assert(model.relationships[0].startArrow)
        action(endArrow)
        assert(!model.relationships[0].endArrow)
        let painted = canvas.dataWithPDF(inside: canvas.bounds)
        assert(painted.count > 1000, "Offscreen AppKit draw must render styled relationship without a window")
        let firstHandle = CGPoint(x: start.x + 60, y: start.y)
        let firstMoved = CGPoint(x: firstHandle.x + 26, y: firstHandle.y - 14)
        canvas.mouseDown(with: event(.leftMouseDown, firstHandle))
        canvas.mouseDragged(with: event(.leftMouseDragged, firstMoved))
        assert(model.relationships[0].control1 == SIMD2(60, 0), "Preview drag must not create repeated Undo snapshots")
        canvas.mouseUp(with: event(.leftMouseUp, firstMoved))
        assert(model.relationships[0].control1 == SIMD2(86, -14) &&
               model.relationships[0].control2 == SIMD2(-60, 0), "First handle changes only first control")
        canvas.undo()
        assert(model.relationships[0].control1 == SIMD2(60, 0), "Control drag is one Undo step")
        let secondHandle = CGPoint(x: end.x - 60, y: end.y)
        let secondMoved = CGPoint(x: secondHandle.x - 22, y: secondHandle.y + 18)
        canvas.mouseDown(with: event(.leftMouseDown, secondHandle))
        canvas.mouseDragged(with: event(.leftMouseDragged, secondMoved))
        canvas.mouseUp(with: event(.leftMouseUp, secondMoved))
        assert(model.relationships[0].control2 == SIMD2(-82, 18) && model.relationships[0].control1 == SIMD2(60, 0),
               "Second handle changes only second control")
        let beforePan = model.relationships[0]
        canvas.shiftViewport(by: CGPoint(x: 35, y: 25))
        let pannedSecond = CGPoint(x: secondMoved.x + 35, y: secondMoved.y + 25)
        canvas.mouseDown(with: event(.leftMouseDown, pannedSecond))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: pannedSecond.x + 10, y: pannedSecond.y - 12)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: pannedSecond.x + 10, y: pannedSecond.y - 12)))
        assert(model.relationships[0].control2 == beforePan.control2 + SIMD2(10, -12),
               "Screen offset must not leak into stored world-space controls")
        action(remove)
        assert(model.relationships.isEmpty && model.roots == [a, b], "Deleting curve cannot delete either node")
        canvas.undo()
        assert(model.relationships.count == 1)
        let restoredCurve = CGPoint(x: middle.x + 35, y: middle.y + 27)
        canvas.mouseDown(with: event(.leftMouseDown, restoredCurve))
        canvas.mouseUp(with: event(.leftMouseUp, restoredCurve))
        assert(canvas.selectedRelationshipID == id, "Click restored curve before targeting keyboard Delete")
        canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{7f}",
            charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!)
        assert(model.relationships.isEmpty && model.roots == [a, b], "Delete targets selected relation")
        let distant = MapModel(roots: [a, b], selected: a.id)
        let wideCanvas = MapCanvas(model: distant)
        wideCanvas.frame = canvas.frame
        let curved = MapRelationship(from: a.id, to: b.id, control1: SIMD2(60, -800),
                                     control2: SIMD2(-60, 160), startArrow: true, endArrow: true)
        assert(distant.setRelationship(curved))
        let fitted = wideCanvas.fitMapInView()
        let worldWidth = mapNodeSize(a, font: mapFont(isRoot: true, node: a)).width
        let fittedFirst = wideCanvas.frameForAccessibility(a.id)!
        let factor = fittedFirst.width / worldWidth
        let control = CGPoint(x: fittedFirst.maxX + 60 * factor,
                              y: fittedFirst.midY - 800 * factor)
        guard factor < 1 && fitted.insetBy(dx: -1, dy: -1).contains(control) else {
            fputs("Fit curve: frame=\(fitted) control=\(control) factor=\(factor)\n", stderr); exit(1)
        }
        func wideEvent(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: wideCanvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        // A synthetic curve right-click reveals its handles at a non-unit zoom.
        let fittedMiddle = CGPoint(x: (fittedFirst.maxX + wideCanvas.frameForAccessibility(b.id)!.minX) / 2,
                                   y: fittedFirst.midY - 240 * factor)
        _ = wideCanvas.menu(for: wideEvent(.rightMouseDown, fittedMiddle))
        assert(wideCanvas.selectedRelationshipID == curved.id)
        wideCanvas.mouseDown(with: wideEvent(.leftMouseDown, control))
        wideCanvas.mouseDragged(with: wideEvent(.leftMouseDragged, CGPoint(x: control.x + 20, y: control.y)))
        wideCanvas.mouseUp(with: wideEvent(.leftMouseUp, CGPoint(x: control.x + 20, y: control.y)))
        assert(abs(distant.relationships[0].control1.x - (60 + Double(20 / factor))) < 0.001,
               "Twenty screen points must translate to 20 / zoom world units")
        let menuModel = MapModel(roots: [a, b], selected: a.id)
        let menuCanvas = MapCanvas(model: menuModel)
        let delegate = AppDelegate()
        _ = delegate.makeWorkbench(canvas: menuCanvas)
        delegate.installMenu()
        let nativeCreate = NSApp.mainMenu!.items.last!.submenu!.item(withTitle: label("Create Relationship"))!
        assert(menuCanvas.contextMenu(for: a.id).item(withTitle: label("Create Relationship")) == nil,
               "A single selected node may not create an incomplete relation")
        assert(menuModel.toggleSelection(b.id))
        assert(NSApp.sendAction(nativeCreate.action!, to: nativeCreate.target, from: nativeCreate) &&
               menuModel.relationships.count == 1, "Native Node menu must share canvas relation creation")
        let child = MapNode(id: UUID(), title: "Tree child", children: [], folded: false)
        let parent = MapNode(id: UUID(), title: "Tree root", children: [child], folded: false)
        let treeModel = MapModel(roots: [parent], selected: parent.id)
        let treeCanvas = MapCanvas(model: treeModel)
        treeCanvas.frame = canvas.frame
        let frames = mapLayout(treeModel.roots)
        let firstBox = frames[0].frame, childBox = frames[1].frame
        let treeLink = CGPoint(x: (firstBox.maxX + childBox.minX) / 2 + 80,
                               y: (firstBox.midY + childBox.maxY - 7) / 2 + 90)
        let treePress = NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: treeLink.x, y: treeCanvas.bounds.height - treeLink.y),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        treeCanvas.mouseDown(with: treePress)
        assert(treeCanvas.selectedRelationshipID == nil && treeModel.relationships.isEmpty,
               "A tree connector must never masquerade as a cross-node relation")
        print("synthetic relation create, menu, select, style, both handles, zoom/pan, fit and delete passed")
    }
}
