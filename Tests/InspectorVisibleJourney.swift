import AppKit
import Darwin

// Run only inside a uniquely owned synthetic .app when desktop focus is safe to take.
@main enum InspectorVisibleJourney {
    static func main() {
        func finish(_ result: String, code: Int32 = 0) -> Never {
            print(result)
            if CommandLine.arguments.count > 1 {
                let receipt = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
                let directory = receipt.deletingLastPathComponent()
                let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
                if directory.path.hasPrefix("/private/tmp/mindmap-inspector-visible-"),
                   receipt.lastPathComponent == "report.txt",
                   attributes?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
                   (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o700,
                   (try? String(contentsOf: directory.appendingPathComponent(".owner"), encoding: .utf8)) ==
                       "mindmap-owned-inspector-visible\n" {
                    try? result.write(to: receipt, atomically: true, encoding: .utf8)
                }
            }
            exit(code)
        }
        guard ProcessInfo.processInfo.environment["MINDMAP_OWNED_FOCUS_PRECHECK"] == "yes",
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            finish("SKIP unsafe desktop focus", code: 77)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let defaults = UserDefaults(suiteName: "local.mindmap.inspector-visible-\(UUID())")!
        defaults.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        let child = MapNode(id: UUID(), title: "Child", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Root", children: [child], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        let delegate = AppDelegate(defaults: defaults)
        let workbench = delegate.makeWorkbench(canvas: canvas)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 650),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentViewController = workbench
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard window.isVisible, window.isKeyWindow,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            finish("FAIL visible/key/frontmost synthetic window", code: 1)
        }
        let inspector = workbench.splitViewItems[2].viewController.view as! StyleInspector
        let tabNames = ["Style", "Notes", "Themes"]
        guard inspector.tabs.segmentCount == tabNames.count,
              (0..<tabNames.count).allSatisfy({ index in
                  inspector.tabs.image(forSegment: index) != nil &&
                  inspector.tabs.toolTip(forSegment: index) == tabNames[index]
              }),
              workbench.splitViewItems[2].isCollapsed,
              let item = canvas.contextMenu(for: root.id).item(withTitle: "Edit Note"),
              app.sendAction(item.action!, to: item.target, from: item) else {
            finish("FAIL native tabs or Edit Note context action", code: 2)
        }
        window.contentView?.layoutSubtreeIfNeeded()
        guard !workbench.splitViewItems[2].isCollapsed, inspector.tabs.selectedSegment == 1,
              window.firstResponder === inspector.noteTextView,
              (260...320).contains(inspector.frame.width) else {
            finish("FAIL Notes focus or 260–320pt sidebar", code: 3)
        }
        inspector.noteTextView.string = "Visible synthetic note"
        inspector.tabs.selectedSegment = 2
        guard app.sendAction(inspector.tabs.action!, to: inspector.tabs.target, from: inspector.tabs),
              canvas.model.roots[0].note == "Visible synthetic note", inspector.themeButtons.count == 3 else {
            finish("FAIL Notes commit or three native theme cards", code: 4)
        }
        inspector.themeButtons[2].performClick(nil)
        guard canvas.model.theme == InspectorTheme.candyland.rawValue else {
            finish("FAIL Candyland selection", code: 5)
        }
        canvas.undo()
        guard canvas.model.theme == nil, inspector.selectNotes(for: root.id),
              inspector.noteTextView.string == "Visible synthetic note" else {
            finish("FAIL theme Undo or persisted Notes", code: 6)
        }
        inspector.tabs.selectedSegment = 0
        guard app.sendAction(inspector.tabs.action!, to: inspector.tabs.target, from: inspector.tabs),
              !inspector.styleScroll.isHidden, inspector.colorPopup.isEnabled,
              inspector.colorPopup.item(withTitle: "More…") != nil else {
            finish("FAIL visible Style color selector", code: 7)
        }
        let rootsBeforePanel = canvas.model.roots
        inspector.colorPopup.selectItem(withTitle: "More…")
        let openedPanel = app.sendAction(inspector.colorPopup.action!, to: inspector.colorPopup.target,
                                         from: inspector.colorPopup)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let panel = NSColorPanel.shared
        let panelPassed = openedPanel && panel.isVisible && canvas.model.roots == rootsBeforePanel &&
            canvas.model.theme == nil && canvas.model.roots[0].note == "Visible synthetic note"
        panel.orderOut(nil)
        guard panelPassed else { finish("FAIL More native color panel or unchanged model", code: 8) }
        window.orderOut(nil)
        finish("PASS visible=true key=true frontmost=true tabs=3 noteContext=true noteCommit=true themeUndo=true sidebar260to320=true moreNativePanel=true")
    }
}
