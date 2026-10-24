import AppKit

@main enum CanvasImageTests {
    static func main() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 16,
                                      bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<16 { for x in 0..<24 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        let data = bitmap.representation(using: .png, properties: [:])!
        let parent = MapNode(id: UUID(), title: "Parent", children: [], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [parent], selected: parent.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1100, height: 720)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mindmap-owned-image-test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        assert(canvas.pasteImageFromPasteboard(pasteboard), "PNG clipboard must create an image node")
        guard let imageNode = canvas.model.roots.first?.children.first,
              let image = imageNode.image else { fatalError("Paste must create one new picture child") }
        assert(imageNode.title == "" && image.data == data,
               "Pure picture nodes begin without placeholder text and retain original bytes")
        let imageFrame = canvas.imageFrameForAccessibility(imageNode.id)!
        assert(imageFrame.width > 0 && imageFrame.height > 0 &&
               imageFrame.maxY <= canvas.frameForAccessibility(imageNode.id)!.maxY)
        canvas.selectAndEdit(imageNode.id)
        guard let editor = canvas.subviews.compactMap({ $0 as? NSTextField }).first else {
            fatalError("Double-click image node must allow optional normal title editing")
        }
        assert(editor.frame.minY >= imageFrame.maxY - 1,
               "Image appears above the editable text title, without overlap")
        canvas.commitEditing()
        let oldPictureWidth = canvas.imageFrameForAccessibility(imageNode.id)!.width
        let box = canvas.imageFrameForAccessibility(imageNode.id)!
        let handle = CGPoint(x: box.maxX, y: box.maxY)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type,
                location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, handle))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: handle.x + 50, y: handle.y)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: handle.x + 50, y: handle.y)))
        assert(canvas.imageFrameForAccessibility(imageNode.id)!.width > oldPictureWidth + 40,
               "Dragging an image-node handle must scale the picture itself, not just create whitespace")
        canvas.undo()
        assert(canvas.imageFrameForAccessibility(imageNode.id)!.width == oldPictureWidth,
               "One Undo restores original picture size")
        canvas.model.selectNodes([parent.id, imageNode.id])
        let group = canvas.frameForAccessibility(imageNode.id)!
        let groupHandle = CGPoint(x: group.maxX - 6, y: group.minY + 5)
        canvas.mouseDown(with: mouse(.leftMouseDown, groupHandle))
        canvas.mouseDragged(with: mouse(.leftMouseDragged,
            CGPoint(x: groupHandle.x + 50, y: groupHandle.y)))
        assert(canvas.imageFrameForAccessibility(imageNode.id)!.width == oldPictureWidth,
               "Multi-selection width preview must not fake an image scale that commit cannot preserve")
        canvas.mouseUp(with: mouse(.leftMouseUp,
            CGPoint(x: groupHandle.x + 50, y: groupHandle.y)))
        assert(canvas.imageFrameForAccessibility(imageNode.id)!.width == oldPictureWidth)
        canvas.undo()
        canvas.undo()
        assert(canvas.model.roots[0].children.isEmpty,
               "One Undo removes the entire inserted picture node, without orphan assets")
        print("picture clipboard node, image-first layout, title editing and atomic Undo passed")
    }
}
