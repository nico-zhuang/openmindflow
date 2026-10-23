import AppKit

@main enum NativeImportVisualTests {
    static func main() {
        let child = MapNode(id: UUID(), title: "Child", children: [], folded: false,
                            location: SIMD2(500, 170))
        let target = MapNode(id: UUID(), title: "Target", children: [], folded: false,
                             location: SIMD2(700, 250))
        let root = MapNode(id: UUID(), title: "Root", children: [child, target], folded: false,
                           location: SIMD2(200, 100))
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        canvas.appearance = NSAppearance(named: .aqua)
        canvas.frame = CGRect(x: 0, y: 0, width: 1100, height: 600)
        let rootFont = MindNodeFontMetadata(family: "STSongti-SC-Regular", pointSize: 36,
            color: nil, alignment: "center", alignmentCode: nil, bold: nil, italic: nil)
        let defaultRoot = MindNodeFontMetadata(family: "Helvetica", pointSize: 22,
            color: [1, 1, 1, 1], alignment: nil, alignmentCode: nil, bold: nil, italic: nil)
        let defaultBranch = MindNodeFontMetadata(family: "STSongti-SC-Regular", pointSize: 28,
            color: nil, alignment: nil, alignmentCode: nil, bold: nil, italic: nil)
        canvas.embeddedTheme = MindNodeThemeMetadata(identifier: UUID(), backgroundColor: nil,
            allowNodeStrokeColorVariation: true,
            baseSubnode: MindNodeThemeStyle(font: defaultBranch, fillColor: nil, stroke: nil),
            mainNodes: [MindNodeThemeStyle(font: defaultRoot, fillColor: nil, stroke: nil)], subnodeLevels: [])
        canvas.nativePresentation = [
            root.id: MindNodePresentation(location: CGPoint(x: 200, y: 100), maxWidth: 300,
                allowToShrinkWidth: true, font: rootFont, styleChangedByUser: false,
                fillColor: [0.32, 0.18, 0.55, 1]),
            child.id: MindNodePresentation(location: CGPoint(x: 500, y: 170), maxWidth: 136,
                allowToShrinkWidth: false, font: nil, styleChangedByUser: false,
                fillColor: nil),
            target.id: MindNodePresentation(location: CGPoint(x: 700, y: 250), maxWidth: 300,
                allowToShrinkWidth: true, font: nil, styleChangedByUser: false,
                fillColor: nil)
        ]
        let rootHit = canvas.frameForAccessibility(root.id)!
        let childHit = canvas.frameForAccessibility(child.id)!
        assert(abs(rootHit.midX - 280) < 1 && abs(rootHit.midY - 190) < 1)
        assert(abs(childHit.midX - 580) < 1 && abs(childHit.midY - 260) < 1)
        assert(abs(childHit.width - 136) < 1, "A manually resized source title keeps its actual width")
        canvas.selectAndEdit(root.id)
        let editor = canvas.subviews.compactMap { $0 as? NSTextField }.first!
        assert(editor.font?.pointSize == 36, "Editing uses the source title size, not app default 20pt")
        assert(editor.alignment == .center)
        var editorRed: CGFloat = 0
        canvas.effectiveAppearance.performAsCurrentDrawingAppearance {
            editorRed = editor.textColor?.usingColorSpace(.deviceRGB)?.redComponent ?? 0
        }
        assert(editorRed > 0.9,
               "White title color inherited from dark embedded theme must remain readable in Light mode")
        canvas.commitEditing()
        canvas.selectAndEdit(child.id)
        let branchEditor = canvas.subviews.compactMap { $0 as? NSTextField }.first!
        assert(branchEditor.font?.pointSize == 28, "Branch without explicit CSS must inherit document theme, not 16pt fallback")
        canvas.commitEditing()
        func mouse(_ kind: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: CGPoint(x: x, y: canvas.bounds.height - y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let handle = canvas.frameForAccessibility(child.id)!
        let handleY = handle.maxY - 7
        canvas.mouseDown(with: mouse(.leftMouseDown, x: handle.maxX, y: handleY))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, x: handle.maxX + 44, y: handleY))
        canvas.mouseUp(with: mouse(.leftMouseUp, x: handle.maxX + 44, y: handleY))
        assert(canvas.model.roots[0].children[0].width == 180, "Dragging the selected right edge changes the individual width")
        assert(canvas.model.undo() && canvas.model.roots[0].children[0].width == nil,
               "One continuous width drag creates exactly one undoable change")
        let middle = canvas.frameForAccessibility(child.id)!
        canvas.mouseDown(with: mouse(.leftMouseDown, x: middle.maxX - 2, y: middle.midY))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, x: middle.maxX + 44, y: middle.midY))
        canvas.mouseUp(with: mouse(.leftMouseUp, x: middle.maxX + 44, y: middle.midY))
        assert(canvas.model.roots[0].children[0].width == nil,
               "Dragging from the card-body edge must not trigger the tiny baseline resize handle")
        let sourceHit = canvas.frameForAccessibility(child.id)!
        let targetHit = canvas.frameForAccessibility(target.id)!
        canvas.mouseDown(with: mouse(.leftMouseDown, x: sourceHit.midX, y: sourceHit.midY))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, x: targetHit.midX, y: targetHit.midY))
        assert(abs(canvas.frameForAccessibility(root.id)!.midX - 280) < 1,
               "A valid imported-tree drag preview must keep unrelated saved roots in place")
        canvas.mouseUp(with: mouse(.leftMouseUp, x: targetHit.midX, y: targetHit.midY))
        let moved = canvas.model.roots[0].children.first(where: { $0.id == target.id })?.children.first
        assert(moved?.id == child.id, "Center drop reparents the imported child once")
        assert((moved?.location?.x ?? 0) > 700 && canvas.frameForAccessibility(child.id)!.minX >= targetHit.maxX,
               "Dropped child must appear beside its new parent instead of overlapping it or snapping back")
        assert(canvas.model.undo() && canvas.model.roots[0].children[0].location == SIMD2(500, 170),
               "Undo restores original MindNode saved position and source parent")
        print("source positions, theme font, drag width, imported reparent and undo passed")
    }
}
