import AppKit

@main enum TabChromeInteractionTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let suite = "local.openmindflow.chrome.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        L10n.setLanguage("en", defaults: defaults)
        let app = AppDelegate(defaults: defaults)
        let owner = app.makeUnshownWindowSession()
        let first = owner.active!
        owner.tabStrip.onNewTab()
        let second = owner.active!
        let strip = owner.tabStrip
        strip.frame = CGRect(x: 0, y: 0, width: 360, height: 36)
        strip.layoutSubtreeIfNeeded()
        func rows() -> [NSView] { strip.subviews.filter { $0.subviews.first is NSButton } }
        let title = rows()[0].subviews[0] as! NSButton
        func click(_ count: Int) {
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                timestamp: 10, windowNumber: owner.window.windowNumber, context: nil,
                eventNumber: 0, clickCount: count, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
                timestamp: 10.1, windowNumber: owner.window.windowNumber, context: nil,
                eventNumber: 1, clickCount: count, pressure: 0)!
            NSApp.postEvent(up, atStart: true)
            title.mouseDown(with: event)
        }
        click(2)
        let editor = rows()[0].subviews.compactMap { $0 as? NSTextField }.first
        assert(editor != nil && owner.active === second, "double-click edits exactly clicked background tab")
        editor!.stringValue = "First renamed"
        assert(owner.window.makeFirstResponder(strip), "blur editor")
        assert(first.displayTabTitle(defaults: defaults) == "First renamed" && second.tabTitleOverride == nil)
        assert(rows()[0].subviews.compactMap { $0 as? NSTextField }.isEmpty)
        let firstTitle = rows()[0].subviews[0] as! NSButton
        let mouse = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
            timestamp: 12, windowNumber: owner.window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 0, pressure: 0)!
        let close = rows()[0].subviews[1]
        assert(close.isHidden && close.hitTest(CGPoint(x: 12, y: 12)) == nil)
        rows()[0].mouseEntered(with: mouse)
        assert(!close.isHidden, "hover exposes close")
        rows()[0].mouseExited(with: mouse)
        rows()[0].mouseEntered(with: mouse)
        assert(!close.isHidden, "re-enter interrupts the outgoing fade")
        let cancelEvent = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 13, windowNumber: owner.window.windowNumber, context: nil,
            eventNumber: 3, clickCount: 2, pressure: 1)!
        firstTitle.mouseDown(with: cancelEvent)
        let cancelField = rows()[0].subviews.compactMap { $0 as? NSTextField }.first!
        cancelField.stringValue = "  "
        assert(!strip.control(cancelField, textShouldEndEditing: NSTextView()),
               "invalid blank title is rejected by the field delegate")
        assert(strip.control(cancelField, textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        assert(rows()[0].subviews.contains { $0 === cancelField }, "invalid Return keeps editor")
        assert(first.displayTabTitle(defaults: defaults) == "First renamed")
        assert(strip.control(cancelField, textView: NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        assert(first.displayTabTitle(defaults: defaults) == "First renamed", "Escape restores title")
        let secondTitle = rows()[1].subviews[0] as! NSButton
        assert(firstTitle.accessibilityCustomActions()?.first?.name == "Close Tab")
        assert(rows()[0].subviews[1] === close, "hovered close stays on its own row")
        assert(rows()[0].subviews[1].frame.width >= 24)
        assert(rows()[1].subviews[1].isHidden)
        assert(secondTitle.state == .on && firstTitle.state == .off)
        assert(!secondTitle.isBordered, "opaque title bezel must not obscure selected accent")
        strip.layoutSubtreeIfNeeded()
        func activePixel(_ row: NSView, appearance: NSAppearance) -> NSColor {
            row.appearance = appearance
            row.needsDisplay = true
            let rep = row.bitmapImageRepForCachingDisplay(in: row.bounds)!
            row.cacheDisplay(in: row.bounds, to: rep)
            return rep.colorAt(x: 8, y: 8)!.usingColorSpace(.deviceRGB)!
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: name)!
            let selected = activePixel(rows()[1], appearance: appearance)
            let unselected = activePixel(rows()[0], appearance: appearance)
            let difference = abs(selected.redComponent - unselected.redComponent) +
                abs(selected.greenComponent - unselected.greenComponent) +
                abs(selected.blueComponent - unselected.blueComponent)
            assert(difference > 0.08, "selected row should have visible accent in \(name.rawValue)")
        }
        secondTitle.mouseDown(with: cancelEvent)
        let entered = rows()[1].subviews.compactMap { $0 as? NSTextField }.first!
        entered.stringValue = "Second Entered"
        owner.refreshTabs()
        assert(rows()[1].subviews.contains { $0 === entered }, "refresh must not destroy a pending inline edit")
        assert(strip.control(entered, textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        assert(second.displayTabTitle(defaults: defaults) == "Second Entered", "Return commits clicked session")
        assert(first.displayTabTitle(defaults: defaults) == "First renamed", "Return cannot rename sibling")
        owner.setOrientation(.vertical)
        strip.frame = CGRect(x: 0, y: 0, width: 180, height: 400)
        strip.layoutSubtreeIfNeeded()
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: name)!
            let selected = activePixel(rows()[1], appearance: appearance)
            let unselected = activePixel(rows()[0], appearance: appearance)
            assert(abs(selected.redComponent - unselected.redComponent) +
                   abs(selected.greenComponent - unselected.greenComponent) +
                   abs(selected.blueComponent - unselected.blueComponent) > 0.08,
                   "vertical selected accent in \(name.rawValue)")
        }
        let plus = strip.subviews.compactMap { $0 as? NSButton }.first!
        assert(abs(plus.frame.midX - strip.bounds.midX) < 1 && plus.frame.minY >= rows().last!.frame.maxY)
        let editingSecond = rows()[1].subviews[0] as! NSButton
        editingSecond.mouseDown(with: cancelEvent)
        let pending = rows()[1].subviews.compactMap { $0 as? NSTextField }.first!
        pending.stringValue = "Second Click Commit"
        let selectFirst = rows()[0].subviews[0] as! NSButton
        let single = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 14, windowNumber: owner.window.windowNumber, context: nil,
            eventNumber: 4, clickCount: 1, pressure: 1)!
        selectFirst.mouseDown(with: single)
        assert(owner.active === first && second.displayTabTitle(defaults: defaults) == "Second Click Commit",
               "blur must commit clicked tab and preserve selection click")
        let stale = title.accessibilityCustomActions()!.first!
        assert(stale.handler?() == false, "detached title must fail closed")
        print("offscreen inline edit, persistent close AX, selected state and vertical geometry passed; physical pointer/VoiceOver unverified")
    }
}
