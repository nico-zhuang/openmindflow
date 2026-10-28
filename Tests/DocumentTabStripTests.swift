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
        // Background save/dirty changes update its tab, never the active window title.
        let activeTitle = a.window.title
        let backgroundURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("task79-background-\(UUID()).mflw")
        defer { try? FileManager.default.removeItem(at: backgroundURL) }
        try! first.saveCurrentMap(to: backgroundURL)
        first.canvas.addMainNode()
        first.onTitleChange?()
        let backgroundButton = strip.subviews.compactMap { $0.subviews.first as? NSButton }
            .first { $0.title.contains(backgroundURL.lastPathComponent) }
        assert(backgroundButton?.title.contains("•") == true && a.window.title == activeTitle,
               "Inactive live document must refresh its tab without replacing the active window title")
        let detachedTitle = a.window.title
        first.window = nil
        first.onTitleChange?()
        assert(a.window.title == detachedTitle, "Detached document cannot change registered window title")
        first.window = a.window
        newest.inspector.noteTextView.string = String(repeating: "界", count: 22_000)
        strip.onSelect(strip.id(for: first))
        assert(a.active === newest, "Invalid pending editor must prevent tab selection")
        newest.inspector.noteTextView.string = ""
        let staleClose = strip.subviews.compactMap { $0.subviews.last as? NSButton }.last!
        strip.onClose(strip.id(for: newest))
        assert(a.documents.count == 1 && a.active === first)
        assert(NSApp.sendAction(staleClose.action!, to: staleClose.target, from: staleClose))
        assert(a.documents.count == 1 && a.active === first,
               "Retained close button from a removed row must not close another document")
        let staleSelect = strip.subviews.compactMap { $0.subviews.first as? NSButton }.first!
        a.refreshTabs()
        assert(NSApp.sendAction(staleSelect.action!, to: staleSelect.target, from: staleSelect))
        assert(a.documents.count == 1 && a.active === first,
               "Detached select button cannot resolve an obsolete row")
        let findItem = NSApp.mainMenu!.item(withTitle: "Edit")!.submenu!.item(withTitle: "Find…")
        app.foregroundWindowForTesting = a.window
        app.selectUnshownSessionForTesting(first)
        if let findItem { assert(NSApp.sendAction(findItem.action!, to: findItem.target, from: findItem)) }
        else { fatalError("Missing Find menu item") }
        let findPanel = first.findWindow!
        app.foregroundWindowForTesting = findPanel
        app.mainWindowForTesting = b.window
        let beforeFind = a.documents.count
        app.newTab(nil)
        assert(a.documents.count == beforeFind + 1 && b.documents.count == 1,
               "Key Find panel targets its active live owner, not a different main document")
        let findCreated = a.active!
        app.closeTab(nil)
        assert(a.documents.contains(where: { $0 === first }) && a.documents.contains(where: { $0 === findCreated }),
               "Find panel may close only when its owning document is still active")
        let settingsItem = NSApp.mainMenu!.items.first!.submenu!.item(withTitle: "Settings…")!
        assert(NSApp.sendAction(settingsItem.action!, to: settingsItem.target, from: settingsItem))
        let settings = NSApp.windows.first { $0.title == "Settings" }!
        app.foregroundWindowForTesting = settings
        app.mainWindowForTesting = nil
        let beforeSettings = app.windowSessions.count
        app.newTab(nil)
        app.closeTab(nil)
        assert(app.windowSessions.count == beforeSettings && a.documents.count == beforeFind + 1 &&
               b.documents.count == 1, "Settings without live main document must fail closed")
        app.mainWindowForTesting = b.window
        app.newTab(nil)
        assert(b.documents.count == 2 && a.documents.count == beforeFind + 1,
               "Settings may use only an explicitly live main document")
        app.closeTab(nil)
        assert(b.documents.count == 1, "Command-W from Settings with live main document closes its tab")
        let unknown = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                               styleMask: [.titled], backing: .buffered, defer: false)
        let counts = [a.documents.count, b.documents.count, c.documents.count]
        let active = [a.active!, b.active!, c.active!]
        func assertUnchanged(_ context: String) {
            assert(app.windowSessions.count == 3 &&
                   [a.documents.count, b.documents.count, c.documents.count] == counts &&
                   a.active === active[0] && b.active === active[1] && c.active === active[2], context)
        }
        app.foregroundWindowForTesting = unknown
        app.newTab(nil)
        assertUnchanged("Command-T from unknown key window must not target a different main document")
        app.closeTab(nil)
        assertUnchanged("Command-W from unknown key window must not close a different main document")
        first.findWindow = nil // Retain the old panel as key after detaching it from its document.
        app.foregroundWindowForTesting = findPanel
        app.newTab(nil)
        assertUnchanged("Command-T from detached Find panel must not target a different main document")
        app.closeTab(nil)
        assertUnchanged("Command-W from detached Find panel must not close a different main document")
        app.foregroundWindowForTesting = NSColorPanel.shared
        app.newTab(nil)
        assert(b.documents.count == counts[1] + 1 && a.documents.count == counts[0],
               "Shared color panel may route Command-T through its live main document")
        app.closeTab(nil)
        assertUnchanged("Shared color panel may route Command-W through its live main document")
        app.foregroundWindowForTesting = nil
        app.mainWindowForTesting = nil
        assert(!a.window.isVisible && !b.window.isVisible && !c.window.isVisible)
        a.window.close()
        let closedCount = a.documents.count
        strip.onNewTab()
        assert(!app.windowSessions.contains(where: { $0 === a }) && a.documents.count == closedCount,
               "Retained plus callback must not create a ghost tab on a closed window")
        print("horizontal/vertical layout, viewport anchor, tab identity, editor rejection, plus and menu bindings passed")
    }
}
