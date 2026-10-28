import AppKit

@main enum DocumentTabStripTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let defaults = UserDefaults(suiteName: "local.openmindflow.tabs.\(UUID())")!
        L10n.setLanguage("en", defaults: defaults)
        let app = AppDelegate(defaults: defaults)
        app.installMenu()
        let a = app.makeUnshownWindowSession(), b = app.makeUnshownWindowSession()
        let first = a.active!, other = b.active!
        let firstModel = first.canvas.model, firstCanvas = first.canvas
        let original = a.window.frame
        let strip = a.tabStrip
        assert(strip.orientation == .horizontal && strip.documents.count == 1)
        assert(a.window.contentViewController?.view === a.tabRoot.view)
        assert(first.splitController.parent === a.tabRoot)
        func screenOrigin() -> CGPoint {
            a.window.contentView?.layoutSubtreeIfNeeded()
            return first.canvas.frameForAccessibility(first.canvas.model.roots[0].id)!.origin
        }
        let start = screenOrigin()
        assert(strip.window === a.window && strip.frame.minY >= first.splitController.view.frame.maxY - 1,
               "Horizontal tabs belong above workbench and inside native toolbar content")
        a.setOrientation(.vertical)
        let vertical = screenOrigin()
        assert(strip.orientation == .vertical && a.window.frame == original)
        assert(strip.frame.maxX <= first.splitController.view.frame.minX + 1,
               "Vertical tabs belong left of, not inside, the workbench split")
        assert(hypot(start.x - vertical.x, start.y - vertical.y) < 1,
               "Orientation must compensate canvas screen anchor")
        for _ in 0..<4 { a.setOrientation(.horizontal); a.setOrientation(.vertical) }
        let repeated = screenOrigin()
        assert(hypot(start.x - repeated.x, start.y - repeated.y) < 1)
        assert(b.orientation == .horizontal && b.active === other && b.window.frame != .zero)
        let c = app.makeUnshownWindowSession()
        assert(c.orientation == .vertical && b.orientation == .horizontal)
        let click = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                       timestamp: 0, windowNumber: a.window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let orientationMenu = strip.menu(for: click)!
        assert(orientationMenu.item(withTitle: "Vertical Tabs")?.state == .on &&
               orientationMenu.item(withTitle: "Horizontal Tabs")?.state == .off)
        assert(strip.insertionIndex(at: CGPoint(x: 0, y: 0)) == 0)
        let file = NSApp.mainMenu!.item(withTitle: "File")!.submenu!
        let newTab = file.item(withTitle: "New Tab")!, closeTab = file.item(withTitle: "Close Tab")!
        assert(newTab.keyEquivalent == "t" && newTab.keyEquivalentModifierMask == [.command] &&
               newTab.action.map(NSStringFromSelector) == "newTab:" && newTab.target as AnyObject? === app)
        assert(closeTab.keyEquivalent == "w" && closeTab.keyEquivalentModifierMask == [.command] &&
               closeTab.action.map(NSStringFromSelector) == "closeTab:" && closeTab.target as AnyObject? === app)
        let before = first.canvas.model.roots.count
        assert(NSApp.mainMenu!.item(withTitle: "Node")!.submenu!.item(withTitle: "New Main Node")!.keyEquivalent.isEmpty)
        assert(first.canvas.model.roots.count == before)
        strip.onNewTab()
        assert(a.documents.count == 2 && a.active !== first && a.active?.canvas.model !== firstModel,
               "The plus action adds exactly one independent tab to its owning window")
        let newest = a.active!
        app.foregroundWindowForTesting = a.window
        assert(NSApp.sendAction(newTab.action!, to: newTab.target, from: newTab))
        assert(a.documents.count == 3 && a.active !== newest)
        assert(NSApp.sendAction(closeTab.action!, to: closeTab.target, from: closeTab))
        assert(a.documents.count == 2 && a.active === first)
        app.foregroundWindowForTesting = nil
        first.canvas.addMainNode()
        assert(first.dirty)
        let rootCount = first.canvas.model.roots.count
        let firstTabButton = strip.subviews.compactMap { $0.subviews.first as? NSButton }.first!
        assert(NSApp.sendAction(firstTabButton.action!, to: firstTabButton.target, from: firstTabButton))
        assert(a.active === first && a.active?.canvas === firstCanvas && a.active?.canvas.model === firstModel &&
               first.dirty && first.canvas.model.roots.count == rootCount)
        first.canvas.undo()
        assert(first.canvas.model.roots.count == rootCount - 1 && !first.dirty,
               "Switching tabs must retain the original undo history")
        first.canvas.redo()
        assert(first.canvas.model.roots.count == rootCount && first.dirty)
        strip.onSelect(strip.id(for: newest))
        assert(a.active === newest && first.dirty)
        newest.inspector.noteTextView.string = String(repeating: "界", count: 22_000)
        strip.onSelect(strip.id(for: first))
        assert(a.active === newest, "Invalid pending editor must prevent tab selection")
        newest.inspector.noteTextView.string = ""
        strip.onClose(strip.id(for: newest))
        assert(a.documents.count == 1 && a.active === first)
        assert(!a.window.isVisible && !b.window.isVisible && !c.window.isVisible)
        print("horizontal/vertical layout, viewport anchor, tab identity, editor rejection, plus and menu bindings passed")
    }
}
