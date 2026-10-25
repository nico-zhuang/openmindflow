import AppKit

@main enum ClipboardCanvasTests {
    static func main() {
        let child = MapNode(id: UUID(), title: "child", children: [], folded: false,
                            location: SIMD2(420, 150))
        let root = MapNode(id: UUID(), title: "root", children: [child], folded: false,
                           location: SIMD2(180, 150))
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1600, height: 900)
        assert(canvas.model.selectNodes([root.id, child.id]))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("local.mindmap.clipboard-synthetic-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        assert(canvas.copySelection(to: pasteboard), "Canvas copies model selection into native clipboard")
        assert(pasteboard.data(forType: NSPasteboard.PasteboardType("local.mindmap.node-group.v1")) != nil,
               "Clipboard payload must be an application-private typed byte stream")
        let blank = CGPoint(x: 1130, y: 520)
        assert(canvas.pasteSelection(from: pasteboard, at: blank), "Paste at blank screen point succeeds")
        assert(canvas.model.roots.count == 2 && canvas.model.selectedIDs == [canvas.model.roots[1].id],
               "The whole new group is selected after canvas paste")
        assert(abs(canvas.frameForAccessibility(canvas.model.roots[1].id)!.midX - blank.x) < 2,
               "Pasted group lands near the clicked blank screen position")
        canvas.undo()
        assert(canvas.model.roots == [root], "One canvas Undo removes the full pasted group")
        pasteboard.clearContents()
        pasteboard.setData(Data("garbage".utf8), forType: NSPasteboard.PasteboardType("local.mindmap.node-group.v1"))
        assert(!canvas.pasteSelection(from: pasteboard, at: blank) && canvas.model.roots == [root],
               "Damaged external clipboard does not mutate the map")
        print("native typed clipboard and screen-anchor paste passed")
    }
}
