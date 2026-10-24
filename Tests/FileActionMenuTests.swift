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
        for title in ["Insert Image…", "Export PDF…", "Export PNG…", "Export JPG…", "Export Markdown…"] {
            guard let action = file.item(withTitle: title), action.target != nil,
                  action.action != nil else { fatalError("Missing native File menu action: \(title)") }
        }
        assert(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu?.item(withTitle: "Paste") != nil,
               "Canvas should receive native Edit → Paste while it is first responder")
        print("native image import and full-map PDF/PNG/JPG/Markdown menu actions passed")
    }
}
