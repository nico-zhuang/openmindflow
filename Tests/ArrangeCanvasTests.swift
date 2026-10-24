import AppKit

@main enum ArrangeCanvasTests {
    static func main() {
        UserDefaults.standard.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        _ = NSApplication.shared
        let one = MapNode(id: UUID(), title: "One", children: [], folded: false,
                          location: SIMD2(410, 300))
        let two = MapNode(id: UUID(), title: "Two", children: [], folded: false,
                          location: SIMD2(410, 300))
        let root = MapNode(id: UUID(), title: "Root", children: [one, two], folded: false,
                           location: SIMD2(110, 270))
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 700)
        let original = canvas.model.roots
        let otherCommands = canvas.contextMenu(for: nil)
        assert(canvas.model.roots == original, "Opening a context menu must never move imported nodes")
        guard let arrange = otherCommands.item(withTitle: "Arrange Map") else {
            fatalError("Blank-canvas right-click must offer an explicit Arrange Map command")
        }
        assert(NSApp.sendAction(arrange.action!, to: arrange.target, from: arrange))
        let positions = canvas.model.roots[0].children.map(\.location)
        assert(positions.count == 2 && positions[0] != positions[1],
               "Explicit arrangement must separate overlapping sibling nodes")
        let boxes = [canvas.frameForAccessibility(one.id)!, canvas.frameForAccessibility(two.id)!]
        assert(boxes[0].maxY + 20 <= boxes[1].minY,
               "Sibling branches need comfortable vertical spacing without overlaps")
        canvas.undo()
        assert(canvas.model.roots == original, "One Undo must exactly restore imported original positions")
        print("explicit Arrange Map, comfortable separation and one-step Undo passed")
    }
}
