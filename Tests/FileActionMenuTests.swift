import AppKit

@main enum FileActionMenuTests {
    static func main() {
        let defaults = UserDefaults(suiteName: "local.mindmap.file-menu-test.\(UUID())")!
        L10n.setLanguage("en", defaults: defaults)
        _ = NSApplication.shared
        let root = MapNode(id: UUID(), title: "Root", children: [], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        let delegate = AppDelegate(defaults: defaults)
        _ = delegate.makeWorkbench(canvas: canvas)
        delegate.installMenu()
        let file = NSApp.mainMenu!.item(withTitle: "File")!.submenu!
        for title in ["New Window", "New Tab", "Close Tab", "Open Map…", "Import MindNode…", "Save", "Save As…", "Save As MindNode Copy…", "Insert Image…", "Insert Video…", "Export MindNode…",
                      "Export PDF…", "Export PNG…", "Export JPG…", "Export Markdown…"] {
            guard let action = file.item(withTitle: title), action.target != nil,
                  action.action != nil else { fatalError("Missing native File menu action: \(title)") }
        }
        let newWindow = file.item(withTitle: "New Window")!
        assert(newWindow.keyEquivalent == "n" && newWindow.keyEquivalentModifierMask == [.command] &&
               newWindow.action.map(NSStringFromSelector) == "newWindow:" && newWindow.target as AnyObject? === delegate)
        let newTab = file.item(withTitle: "New Tab")!, closeTab = file.item(withTitle: "Close Tab")!
        assert(newTab.keyEquivalent == "t" && newTab.keyEquivalentModifierMask == [.command] &&
               newTab.action.map(NSStringFromSelector) == "newTab:" && newTab.target as AnyObject? === delegate)
        assert(closeTab.keyEquivalent == "w" && closeTab.keyEquivalentModifierMask == [.command] &&
               closeTab.action.map(NSStringFromSelector) == "closeTab:" && closeTab.target as AnyObject? === delegate)
        assert(NSApp.mainMenu!.item(withTitle: "Node")!.submenu!.item(withTitle: "New Main Node")!.keyEquivalent.isEmpty)
        for removed in ["Open Own JSON…", "Open MindNode (Read-only)…",
                        "Experimental MindNode v9 Plain-Tree Copy…"] {
            assert(file.item(withTitle: removed) == nil, "Superseded format label must not remain: \(removed)")
        }
        assert(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu?.item(withTitle: "Paste") != nil,
               "Canvas should receive native Edit → Paste while it is first responder")
        print("native mflw, editable MindNode import, preservation export, and media menu actions passed")
    }
}
