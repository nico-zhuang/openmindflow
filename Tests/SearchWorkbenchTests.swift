import AppKit

@main enum SearchWorkbenchTests {
    static func main() {
        let defaults = UserDefaults(suiteName: "local.mindmap.find-test.\(UUID())")!
        L10n.setLanguage("en", defaults: defaults)
        _ = NSApplication.shared
        let child = MapNode(id: UUID(), title: "折叠的 Alpha résumé", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Root", children: [child], folded: true)
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        let delegate = AppDelegate(defaults: defaults)
        let workbench = delegate.makeWorkbench(canvas: canvas)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = workbench
        delegate.installMenu()
        let find = NSApp.mainMenu!.item(withTitle: "Edit")!.submenu!.item(withTitle: "Find…")!
        assert(find.keyEquivalent == "f" && find.keyEquivalentModifierMask.contains(.command))
        assert(NSApp.sendAction(find.action!, to: find.target, from: find))
        guard let searchWindow = NSApp.windows.first(where: { $0.title == "Find" }),
              let field = searchWindow.contentView?.subviews.compactMap({ $0 as? NSSearchField }).first else {
            fatalError("Cmd+F must open a native, editable search field")
        }
        field.stringValue = "resume"
        assert(NSApp.sendAction(field.action!, to: field.target, from: field))
        assert(canvas.model.selected == child.id &&
               canvas.frameForAccessibility(child.id) != nil,
               "A title search must navigate even into formerly folded descendants")
        let replacement = MapNode(id: UUID(), title: "Second document", children: [], folded: false)
        canvas.model = MapModel(roots: [replacement], selected: replacement.id)
        let next = searchWindow.contentView!.subviews.compactMap { $0 as? NSButton }.first!
        assert(NSApp.sendAction(next.action!, to: next.target, from: next))
        let count = searchWindow.contentView!.subviews.compactMap { $0 as? NSTextField }
            .first(where: { !($0 is NSSearchField) })!
        assert(count.stringValue == "No matches" && canvas.model.selected == replacement.id,
               "Find Next must drop stale UUIDs and counts immediately after document replacement")
        field.stringValue = "second"
        assert(NSApp.sendAction(field.action!, to: field.target, from: field))
        assert(count.stringValue == "1 / 1" && canvas.model.selected == replacement.id)
        searchWindow.orderOut(nil)
        window.orderOut(nil)
        print("global native Find and folded-result navigation passed")
    }
}
