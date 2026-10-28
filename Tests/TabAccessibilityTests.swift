import AppKit

@main enum TabAccessibilityTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let suite = "local.openmindflow.ax-tabs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = L10n.setLanguage("en", defaults: defaults)
        let app = AppDelegate(defaults: defaults)
        app.installMenu()
        let a = app.makeUnshownWindowSession(), b = app.makeUnshownWindowSession()
        let first = a.active!, secondWindowDocument = b.active!
        a.tabStrip.onNewTab()
        let second = a.active!
        let firstID = a.tabStrip.id(for: first), secondID = a.tabStrip.id(for: second)
        first.canvas.addMainNode()
        assert(first.dirty && a.active === second)

        func controls(_ owner: WindowSession) -> [(NSButton, NSButton)] {
            owner.tabStrip.subviews.compactMap { row in
                guard row.subviews.count == 2,
                      let title = row.subviews[0] as? NSButton,
                      let close = row.subviews[1] as? NSButton else { return nil }
                return (title, close)
            }
        }
        func check(_ language: String, untitled: String, modified: String,
                   close: String, new: String, horizontal: String, vertical: String) {
            let rows = controls(a), other = controls(b)
            assert(rows.count == 2 && other.count == 1)
            assert(a.tabStrip.accessibilityRole() == .tabGroup)
            for (index, row) in rows.enumerated() {
                assert(row.0.accessibilityRole() == .radioButton)
                assert(row.0.accessibilityLabel() == untitled + (index == 0 ? ", " + modified : ""),
                       "\(language) tab name and dirty status must be announced")
                assert(row.0.state == (index == 1 ? .on : .off), "selected state must reflect active document")
                assert(row.1.accessibilityLabel() == close + ": " + untitled)
                assert(row.0.accessibilityCustomActions()?.first?.name == close,
                       "tab title exposes Close even when hover-only button is hidden")
                assert(row.1.isHidden, "at-rest close control cannot intercept pointer input")
                assert(row.1.action != nil && row.1.target as AnyObject? === a.tabStrip)
            }
            assert(other[0].0.accessibilityLabel() == untitled && other[0].0.state == .on)
            assert(other[0].1.accessibilityLabel() == close + ": " + untitled)
            let plus = a.tabStrip.subviews.compactMap { $0 as? NSButton }.single!
            assert(plus.accessibilityLabel() == new && plus.action != nil)
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                           timestamp: 0, windowNumber: a.window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let menu = a.tabStrip.menu(for: event)!
            assert(menu.item(withTitle: horizontal)?.state == (a.orientation == .horizontal ? .on : .off))
            assert(menu.item(withTitle: vertical)?.state == (a.orientation == .vertical ? .on : .off))
            assert(menu.items.allSatisfy { $0.keyEquivalent.isEmpty }, "do not collide with Hide Others or paste shortcuts")
            let actions = a.tabStrip.accessibilityCustomActions() ?? []
            assert(actions.map(\.name) == [horizontal, vertical], "orientation must be available through keyboard-accessible AX actions")
            assert(a.tabStrip.acceptsFirstResponder, "tab strip must accept keyboard focus")
            a.window.recalculateKeyViewLoop()
            assert(a.tabStrip.canBecomeKeyView && a.tabStrip.nextValidKeyView != nil &&
                   a.tabStrip.previousValidKeyView != nil,
                   "tab strip must belong to the synthetic AppKit key-view loop")
            assert(!a.tabStrip.accessibilityPerformShowMenu(), "never open native menus from an unshown fixture")
        }
        check("en", untitled: "Untitled", modified: "Modified", close: "Close Tab", new: "New Tab",
              horizontal: "Horizontal Tabs", vertical: "Vertical Tabs")
        let row = controls(a)[0].0
        assert(NSApp.sendAction(row.action!, to: row.target, from: row))
        assert(a.active === first && a.tabStrip.selectedID == firstID)
        let plus = a.tabStrip.subviews.compactMap { $0 as? NSButton }.single!
        assert(NSApp.sendAction(plus.action!, to: plus.target, from: plus))
        assert(a.documents.count == 3)
        let newestClose = controls(a)[2].1
        assert(NSApp.sendAction(newestClose.action!, to: newestClose.target, from: newestClose))
        assert(a.documents.count == 2 && a.active === first)
        _ = a.activate(second)
        assert(a.tabStrip.selectedID == secondID)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option],
                                   timestamp: 0, windowNumber: a.window.windowNumber, context: nil,
                                   characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
        assert(!a.tabStrip.performKeyEquivalent(with: key) && a.orientation == .horizontal,
               "canvas/editor focus must not be intercepted by tab orientation keys")
        assert(a.window.makeFirstResponder(a.tabStrip))
        assert(!a.tabStrip.performKeyEquivalent(with: key), "focused strip must not hijack application shortcuts")
        assert(a.tabStrip.accessibilityCustomActions()?.last?.handler?() == true)
        assert(a.orientation == .vertical)
        assert(b.orientation == .horizontal, "orientation command must remain with its owner")
        assert(a.window.makeFirstResponder(second.canvas))
        assert(!a.tabStrip.performKeyEquivalent(with: key) && a.orientation == .vertical)
        check("en", untitled: "Untitled", modified: "Modified", close: "Close Tab", new: "New Tab",
              horizontal: "Horizontal Tabs", vertical: "Vertical Tabs")
        _ = L10n.setLanguage("zh-Hans", defaults: defaults)
        app.installMenu()
        app.refreshLanguageForAllDocuments()
        assert(a.active === second && b.active === secondWindowDocument && a.tabStrip.selectedID == secondID)
        check("zh-Hans", untitled: "未命名", modified: "已修改", close: "关闭标签", new: "新建标签",
              horizontal: "水平标签", vertical: "垂直标签")
        assert(L10n.text("Rename Tab", defaults: defaults) == "重命名标签",
               "inline rename accessibility label must be localized")
        let renameTitle = controls(a)[0].0
        let doubleClick = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 10, windowNumber: a.window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 2, pressure: 1)!
        renameTitle.mouseDown(with: doubleClick)
        let renameField = renameTitle.superview!.subviews.compactMap { $0 as? NSTextField }.first!
        assert(renameField.accessibilityLabel() == "重命名标签")
        assert(a.tabStrip.control(renameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        let zhKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option],
                                     timestamp: 0, windowNumber: a.window.windowNumber, context: nil,
                                     characters: "h", charactersIgnoringModifiers: "h", isARepeat: false, keyCode: 4)!
        assert(a.window.makeFirstResponder(a.tabStrip))
        assert(!a.tabStrip.performKeyEquivalent(with: zhKey), "Command-Option-H belongs to Hide Others, not tabs")
        assert(a.tabStrip.accessibilityCustomActions()?.first?.handler?() == true && a.orientation == .horizontal)
        assert(b.orientation == .horizontal && b.active === secondWindowDocument)
        let detachedStrip = DocumentTabStrip(frame: .zero)
        var detachedCalls = 0
        detachedStrip.onOrientationChange = { _ in detachedCalls += 1 }
        assert(detachedStrip.accessibilityCustomActions()?.last?.handler?() == false && detachedCalls == 0,
               "orientation actions reject strips without a registered live window owner")
        let staleAction = b.tabStrip.accessibilityCustomActions()!.last!
        let staleClose = controls(b)[0].0.accessibilityCustomActions()!.first!
        let staleMenuItem = b.tabStrip.menu(for: zhKey)!.item(withTitle: "垂直标签")!
        b.window.close()
        assert(staleAction.handler?() == false, "closed tabs reject delayed accessibility operations")
        assert(staleClose.handler?() == false, "closed source rejects delayed Close action")
        assert(NSApp.sendAction(staleMenuItem.action!, to: staleMenuItem.target, from: staleMenuItem))
        assert(b.orientation == .horizontal, "closed tabs reject delayed context-menu actions")
        print("offscreen EN/ZH tab AX names, states, guarded orientation handlers and all-window language refresh passed; physical keyboard menu unverified")
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}