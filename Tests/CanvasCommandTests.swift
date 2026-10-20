import AppKit

@main
enum CanvasCommandTests {
    static func main() {
        _ = NSApplication.shared // Initialize AppKit without creating or running a window.
        let rootID = UUID(), childID = UUID()
        let model = MapModel(roots: [MapNode(id: rootID, title: "Root", children: [
            MapNode(id: childID, title: "Existing", children: [], folded: false)
        ], folded: false)], selected: childID)
        let canvas = MapCanvas(model: model)
        let control = NSTextField()
        let text = NSTextView()
        canvas.selectAndEdit(childID)
        let field = canvas.subviews.compactMap { $0 as? NSTextField }.first!
        field.stringValue = "Committed child"
        assert(canvas.control(control, textView: text,
            doCommandBy: NSSelectorFromString("insertTabIgnoringFieldEditor:")))
        let parentID = model.selected
        assert(parentID != childID && model.roots[0].children[0].id == parentID)
        assert(model.roots[0].children[0].children.map(\.id) == [childID])
        assert(model.roots[0].children[0].children[0].title == "Committed child")
        canvas.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "Committed parent"
        assert(canvas.control(control, textView: text,
            doCommandBy: NSSelectorFromString("insertNewlineIgnoringFieldEditor:")))
        assert(model.roots[0].children.map(\.id) == [model.selected, parentID])
        assert(model.roots[0].children[1].title == "Committed parent")
        assert(!canvas.control(control, textView: text,
            doCommandBy: NSSelectorFromString("unrecognizedCommand:")))
        let appDelegate = AppDelegate()
        appDelegate.installMenu()
        let nodeMenu = NSApp.mainMenu!.items.compactMap(\.submenu).first { $0.title == "Node" }!
        let before = nodeMenu.item(withTitle: "New Sibling Before")!
        assert(before.keyEquivalent == "\r" && before.keyEquivalentModifierMask == [.option])
        let parent = nodeMenu.item(withTitle: "New Parent")!
        assert(parent.keyEquivalent == "\t" && parent.keyEquivalentModifierMask == [.option])
        let main = nodeMenu.item(withTitle: "New Main Node")!
        assert(main.keyEquivalent == "\r" && main.keyEquivalentModifierMask == [.shift])
        print("canvas command tests passed (no windows)")
    }
}
