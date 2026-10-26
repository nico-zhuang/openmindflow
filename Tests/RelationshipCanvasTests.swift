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
        let overrides = Dictionary(uniqueKeysWithValues: [a, b].map {
            ($0.id, MapLayoutOverride(location: nil, maxWidth: nil, allowToShrinkWidth: true,
                                      font: mapFont(isRoot: true, node: $0)))
        })
        let worldBoxes = Dictionary(uniqueKeysWithValues: mapLayout(model.roots, overrides: overrides).map { ($0.node.id, $0.frame) })
        func screenControl(_ geometry: RelationshipGeometry, firstHandle: Bool) -> CGPoint {
            let point = firstHandle ? geometry.control1 : geometry.control2
            return CGPoint(x: point.x + first.minX - worldBoxes[a.id]!.minX,
                           y: point.y + first.minY - worldBoxes[a.id]!.minY)
        }
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
        guard let colors = menu.item(withTitle: label("Color"))?.submenu,
              ["Teal", "Blue", "Coral", "Gold", "Gray", "More…"].allSatisfy({ colors.item(withTitle: label($0)) != nil }),
              let blue = colors.item(withTitle: label("Blue")),
              let more = colors.item(withTitle: label("More…")), more.target === canvas,
              more.action != nil, NSApp.windows.isEmpty else {
            fputs("RED: Relationship color submenu must contain five presets and More\n", stderr); exit(1)
        }
        guard let style = menu.item(withTitle: label("Line Style"))?.submenu,
              let dotted = style.item(withTitle: label("Dotted")),
              let startArrow = menu.item(withTitle: label("Start Arrow")),
              let endArrow = menu.item(withTitle: label("End Arrow")),
              let remove = menu.item(withTitle: label("Delete Relationship")) else {
            fputs("RED: Curve right-click must expose style, both arrows and deletion\n", stderr); exit(1)
        }
        action(blue)
        assert(model.relationships[0].color == "#3478F6FF" && model.roots == [a, b] && model.undo() &&
               model.relationships[0].color == nil, "Preset color changes only relation and undoes in one step")
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
        let firstCurve = relationshipGeometry(model.relationships[0], from: worldBoxes[a.id]!, to: worldBoxes[b.id]!)!
        let firstNow = screenControl(firstCurve, firstHandle: true)
        assert(abs(firstNow.x - firstMoved.x) < 1 && abs(firstNow.y - firstMoved.y) < 1 &&
               model.relationships[0].control2 == SIMD2(-60, 0),
               "First handle follows the mouse while the anchor slides on the source outline")
        canvas.undo()
        assert(model.relationships[0].control1 == SIMD2(60, 0), "Control drag is one Undo step")
        let crossedHandle = CGPoint(x: first.minX - 50, y: first.midY)
        canvas.mouseDown(with: event(.leftMouseDown, firstHandle))
        canvas.mouseDragged(with: event(.leftMouseDragged, crossedHandle))
        canvas.mouseUp(with: event(.leftMouseUp, crossedHandle))
        let crossedCurve = relationshipGeometry(model.relationships[0], from: worldBoxes[a.id]!, to: worldBoxes[b.id]!)!
        let crossedNow = screenControl(crossedCurve, firstHandle: true)
        assert(abs(crossedNow.x - crossedHandle.x) < 1 && abs(crossedNow.y - crossedHandle.y) < 1 &&
               crossedCurve.start.x == worldBoxes[a.id]!.minX,
               "Dragging a handle across its source must retain the pointer and slide the anchor to the opposite edge")
        canvas.undo()
        assert(model.relationships[0].control1 == SIMD2(60, 0), "Crossing the source must also undo in one step")
        let secondHandle = CGPoint(x: end.x - 60, y: end.y)
        let secondMoved = CGPoint(x: secondHandle.x - 22, y: secondHandle.y + 18)
        canvas.mouseDown(with: event(.leftMouseDown, secondHandle))
        canvas.mouseDragged(with: event(.leftMouseDragged, secondMoved))
        canvas.mouseUp(with: event(.leftMouseUp, secondMoved))
        let secondCurve = relationshipGeometry(model.relationships[0], from: worldBoxes[a.id]!, to: worldBoxes[b.id]!)!
        let secondNow = screenControl(secondCurve, firstHandle: false)
        assert(abs(secondNow.x - secondMoved.x) < 1 && abs(secondNow.y - secondMoved.y) < 1 &&
               model.relationships[0].control1 == SIMD2(60, 0),
               "Second handle follows the mouse and changes no source-side control")
        let beforePan = model.relationships[0]
        canvas.shiftViewport(by: CGPoint(x: 35, y: 25))
        let pannedSecond = CGPoint(x: secondMoved.x + 35, y: secondMoved.y + 25)
        canvas.mouseDown(with: event(.leftMouseDown, pannedSecond))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: pannedSecond.x + 10, y: pannedSecond.y - 12)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: pannedSecond.x + 10, y: pannedSecond.y - 12)))
        let pannedCurve = relationshipGeometry(model.relationships[0], from: worldBoxes[a.id]!, to: worldBoxes[b.id]!)!
        let pannedHandle = screenControl(pannedCurve, firstHandle: false)
        assert(abs(pannedHandle.x + 35 - pannedSecond.x - 10) < 1 &&
               abs(pannedHandle.y + 25 - pannedSecond.y + 12) < 1 &&
               model.relationships[0].control2 != beforePan.control2,
               "Pan cannot leak into stored world geometry or detach a dragged contour handle from the pointer")
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
        let worldWidth = mapNodeSize(a, font: mapFont(isRoot: true, node: a), isRoot: true).width
        let fittedFirst = wideCanvas.frameForAccessibility(a.id)!
        let factor = fittedFirst.width / worldWidth
        let wideGeometry = relationshipGeometry(curved, from: worldBoxes[a.id]!, to: worldBoxes[b.id]!)!
        func fittedScreen(_ point: CGPoint) -> CGPoint {
            CGPoint(x: fittedFirst.minX + (point.x - worldBoxes[a.id]!.minX) * factor,
                    y: fittedFirst.minY + (point.y - worldBoxes[a.id]!.minY) * factor)
        }
        let control = fittedScreen(wideGeometry.control1)
        guard factor < 1 && fitted.insetBy(dx: -1, dy: -1).contains(control) else {
            fputs("Fit curve: frame=\(fitted) control=\(control) factor=\(factor)\n", stderr); exit(1)
        }
        func wideEvent(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: wideCanvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        // A synthetic curve right-click reveals its handles at a non-unit zoom.
        let midpoint = CGPoint(x: (wideGeometry.start.x + 3 * wideGeometry.control1.x +
                                      3 * wideGeometry.control2.x + wideGeometry.end.x) / 8,
                               y: (wideGeometry.start.y + 3 * wideGeometry.control1.y +
                                      3 * wideGeometry.control2.y + wideGeometry.end.y) / 8)
        _ = wideCanvas.menu(for: wideEvent(.rightMouseDown, fittedScreen(midpoint)))
        assert(wideCanvas.selectedRelationshipID == curved.id)
        wideCanvas.mouseDown(with: wideEvent(.leftMouseDown, control))
        wideCanvas.mouseDragged(with: wideEvent(.leftMouseDragged, CGPoint(x: control.x + 20, y: control.y)))
        wideCanvas.mouseUp(with: wideEvent(.leftMouseUp, CGPoint(x: control.x + 20, y: control.y)))
        let movedWide = relationshipGeometry(distant.relationships[0], from: worldBoxes[a.id]!, to: worldBoxes[b.id]!)!
        assert(abs(movedWide.control1.x - wideGeometry.control1.x - 20 / factor) < 1 &&
               abs(movedWide.control1.y - wideGeometry.control1.y) < 1,
               "At reduced zoom the actual handle must move twenty screen points, independent of its sliding anchor")
        let paintModel = MapModel(roots: [a, b], selected: a.id)
        let paintCanvas = MapCanvas(model: paintModel)
        paintCanvas.frame = canvas.frame
        assert(paintModel.toggleSelection(b.id))
        paintCanvas.createRelationship(nil)
        var paintEdge = paintModel.relationships[0]
        paintEdge.control1 = SIMD2(80, -130)
        paintEdge.control2 = SIMD2(-70, 120)
        paintEdge.endArrow = false
        paintEdge.color = "#FF0000FF"
        assert(paintModel.setRelationship(paintEdge))
        let paintCurve = relationshipGeometry(paintEdge, from: worldBoxes[a.id]!, to: worldBoxes[b.id]!)!
        let paintedFirst = paintCanvas.frameForAccessibility(a.id)!
        func onPaintCanvas(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + paintedFirst.minX - worldBoxes[a.id]!.minX,
                    y: point.y + paintedFirst.minY - worldBoxes[a.id]!.minY)
        }
        func bitmap() -> NSBitmapImageRep {
            let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 700,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: result)
            paintCanvas.draw(paintCanvas.bounds)
            NSGraphicsContext.current = previous
            return result
        }
        func pixel(_ image: NSBitmapImageRep, _ point: CGPoint) -> NSColor {
            image.colorAt(x: Int(point.x.rounded()), y: image.pixelsHigh - 1 - Int(point.y.rounded()))!
                .usingColorSpace(.deviceRGB)!
        }
        let startGuide = onPaintCanvas(CGPoint(x: (paintCurve.start.x + paintCurve.control1.x) / 2,
                                              y: (paintCurve.start.y + paintCurve.control1.y) / 2))
        let endGuide = onPaintCanvas(CGPoint(x: (paintCurve.end.x + paintCurve.control2.x) / 2,
                                            y: (paintCurve.end.y + paintCurve.control2.y) / 2))
        let selectedImage = bitmap()
        assert(paintCanvas.selectNode(a.id) && paintCanvas.selectedRelationshipID == nil)
        let unselectedImage = bitmap()
        for point in [startGuide, endGuide] {
            let selectedPixel = pixel(selectedImage, point), unselectedPixel = pixel(unselectedImage, point)
            assert(abs(selectedPixel.redComponent - unselectedPixel.redComponent) +
                   abs(selectedPixel.greenComponent - unselectedPixel.greenComponent) +
                   abs(selectedPixel.blueComponent - unselectedPixel.blueComponent) > 0.2,
                   "Only selected relationship paints its own anchor-to-control guide")
        }
        let curveMidpoint = onPaintCanvas(CGPoint(x: (paintCurve.start.x + 3 * paintCurve.control1.x +
            3 * paintCurve.control2.x + paintCurve.end.x) / 8,
            y: (paintCurve.start.y + 3 * paintCurve.control1.y + 3 * paintCurve.control2.y + paintCurve.end.y) / 8))
        func hasStroke(_ image: NSBitmapImageRep, red: Bool) -> Bool {
            (-4...4).contains { dx in (-4...4).contains { dy in
                let color = pixel(image, CGPoint(x: curveMidpoint.x + CGFloat(dx), y: curveMidpoint.y + CGFloat(dy)))
                return red ? color.redComponent > 0.8 && color.greenComponent < 0.2 :
                    color.greenComponent > 0.6 && color.redComponent < 0.2
            } }
        }
        assert(hasStroke(selectedImage, red: true) && hasStroke(unselectedImage, red: true),
               "Selected and unselected cubic strokes must keep the actual red color")
        paintEdge.color = "#00EE00FF"
        assert(paintModel.setRelationship(paintEdge) && hasStroke(bitmap(), red: false),
               "A changed edge color must paint the unselected cubic green")
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
