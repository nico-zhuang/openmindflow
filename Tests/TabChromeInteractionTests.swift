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
        // Ordered but non-key windows must retain the editor (accessory test processes do not activate).
        let ordered = app.makeUnshownWindowSession()
        ordered.window.orderFront(nil)
        let orderedStrip = ordered.tabStrip
        orderedStrip.frame = CGRect(x: 0, y: 0, width: 360, height: 36)
        orderedStrip.layoutSubtreeIfNeeded()
        let orderedRow = orderedStrip.subviews.first { $0.subviews.first is NSButton }!
        let orderedTitle = orderedRow.subviews[0] as! NSButton
        let orderedDouble = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 9, windowNumber: ordered.window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 2, pressure: 1)!
        FileHandle.standardError.write(Data("rename boundary before: visible=\(ordered.window.isVisible), key=\(ordered.window.isKeyWindow), active=\(NSApp.isActive)\n".utf8))
        assert(ordered.window.isVisible && !ordered.window.isKeyWindow)
        orderedTitle.mouseDown(with: orderedDouble)
        FileHandle.standardError.write(Data("rename boundary after: firstResponder=\(String(describing: ordered.window.firstResponder)), subviews=\(orderedRow.subviews.map { String(describing: type(of: $0)) })\n".utf8))
        assert(orderedRow.subviews.contains { $0 is NSTextField }, "visible non-key double-click must preserve inline editor")
        ordered.window.orderOut(nil)
        click(2)
        let editor = rows()[0].subviews.compactMap { $0 as? NSTextField }.first
        assert(editor != nil && owner.active === second, "double-click edits exactly clicked background tab")
        editor!.stringValue = "First renamed"
        assert(owner.window.makeFirstResponder(strip), "blur editor")
        assert(first.displayTabTitle(defaults: defaults) == "First renamed" && second.tabTitleOverride == nil)
        assert(rows()[0].subviews.compactMap { $0 as? NSTextField }.isEmpty)
        var firstTitle = rows()[0].subviews[0] as! NSButton
        firstTitle.mouseDown(with: orderedDouble)
        let liveField = rows()[0].subviews.compactMap { $0 as? NSTextField }.first!
        liveField.stringValue = "Stale control"
        let liveEditor = NSTextView()
        liveEditor.string = "  Live editor  "
        assert(strip.control(liveField, textShouldEndEditing: liveEditor), "delegate must inspect current field-editor text")
        assert(strip.control(liveField, textView: liveEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        assert(first.displayTabTitle(defaults: defaults) == "Live editor", "Return must commit normalized live field-editor text")
        (rows()[0].subviews[0] as! NSButton).mouseDown(with: orderedDouble)
        let invalidField = rows()[0].subviews.compactMap { $0 as? NSTextField }.first!
        invalidField.stringValue = "Stale but valid"
        liveEditor.string = "  "
        assert(!strip.control(invalidField, textShouldEndEditing: liveEditor), "blank live editor rejects stale valid control")
        assert(strip.control(invalidField, textView: liveEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        assert(rows()[0].subviews.contains { $0 === invalidField } && first.displayTabTitle(defaults: defaults) == "Live editor")
        _ = strip.control(invalidField, textView: liveEditor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        firstTitle = rows()[0].subviews[0] as! NSButton
        owner.window.orderFront(nil)
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
        rows()[0].mouseExited(with: mouse)
        rows()[0].mouseEntered(with: mouse)
        RunLoop.current.run(until: Date().addingTimeInterval(0.065))
        rows()[0].mouseExited(with: mouse)
        RunLoop.current.run(until: Date().addingTimeInterval(0.075))
        // Unbundled AppKit may finish animator transactions immediately: assert settled
        // hit testing, then prove a subsequent enter is not hidden by an older completion.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        assert(close.isHidden && close.hitTest(CGPoint(x: 12, y: 12)) == nil,
               "latest exit ends hidden and non-hittable")
        rows()[0].mouseEntered(with: mouse)
        RunLoop.current.run(until: Date().addingTimeInterval(0.16))
        assert(!close.isHidden, "settled re-enter remains visible")
        owner.window.orderOut(nil)
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
        assert(first.displayTabTitle(defaults: defaults) == "Live editor")
        assert(strip.control(cancelField, textView: NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        assert(first.displayTabTitle(defaults: defaults) == "Live editor", "Escape restores title")
        let secondTitle = rows()[1].subviews[0] as! NSButton
        assert(firstTitle.accessibilityCustomActions()?.first?.name == "Close Tab")
        assert(rows()[0].subviews[1] === close, "hovered close stays on its own row")
        assert(rows()[0].subviews[1].frame.width >= 24)
        assert(rows()[1].subviews[1].isHidden)
        assert(secondTitle.state == .on && firstTitle.state == .off)
        assert(!secondTitle.isBordered, "opaque title bezel must not obscure selected accent")
        strip.layoutSubtreeIfNeeded()
        func activePixel(_ row: NSView, appearance: NSAppearance) -> NSColor {
            // Render the row ON an opaque native window background, not transparent pixels.
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(row.bounds.width),
                pixelsHigh: Int(row.bounds.height), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            let previousAppearance = NSAppearance.current
            NSAppearance.current = appearance
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor.windowBackgroundColor.setFill()
            row.bounds.fill()
            row.appearance = appearance
            row.draw(row.bounds)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            NSAppearance.current = previousAppearance
            let pixel = rep.colorAt(x: 8, y: 8)!.usingColorSpace(.deviceRGB)!
            assert(pixel.alphaComponent > 0.99, "sample must include opaque composited background")
            return pixel
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
        assert(first.renameTab(to: "Sibling latest"))
        first.canvas.addMainNode()
        assert(rows()[1].subviews.contains { $0 === entered }, "sibling updates cannot discard the editor")
        let siblingTitle = rows()[0].subviews[0] as! NSButton
        assert(siblingTitle.title.contains("Sibling latest") && siblingTitle.title.contains("•") &&
               siblingTitle.accessibilityLabel() == "Sibling latest, Modified" &&
               rows()[0].subviews[1].accessibilityLabel() == "Close Tab: Sibling latest",
               "sibling title, dirty status, AX and Close label refresh during edit")
        let enteredEditor = NSTextView()
        enteredEditor.string = entered.stringValue
        assert(strip.control(entered, textView: enteredEditor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        assert(second.displayTabTitle(defaults: defaults) == "Second Entered", "Return commits clicked session")
        assert(first.displayTabTitle(defaults: defaults) == "Sibling latest", "Return cannot rename sibling")
        let structuralTitle = rows()[1].subviews[0] as! NSButton
        structuralTitle.mouseDown(with: cancelEvent)
        let structuralField = rows()[1].subviews.compactMap { $0 as? NSTextField }.first!
        structuralField.stringValue = "Before structural update"
        owner.tabStrip.onNewTab()
        assert(second.displayTabTitle(defaults: defaults) == "Before structural update" &&
               !rows().contains(where: { $0.subviews.contains { $0 === structuralField } }) &&
               rows().count == 3, "new-tab update explicitly commits valid pending edit before rebuilding")
        let third = owner.active!
        _ = owner.activate(second)
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
        let reorderTitle = rows()[1].subviews[0] as! NSButton
        reorderTitle.mouseDown(with: cancelEvent)
        let reorderField = rows()[1].subviews.compactMap { $0 as? NSTextField }.first!
        reorderField.stringValue = "Reordered pending"
        owner.transferReorder(from: 1, to: 0)
        assert(rows()[0].subviews[0] is NSButton &&
               (rows()[0].subviews[0] as! NSButton).title.contains("Reordered pending") &&
               second.displayTabTitle(defaults: defaults) == "Reordered pending" &&
               !rows().contains(where: { $0.subviews.contains { $0 === reorderField } }),
               "reorder commits the owned edit and cannot leave ghost callbacks")
        assert(third !== second)
        let stale = title.accessibilityCustomActions()!.first!
        assert(stale.handler?() == false, "detached title must fail closed")
        print("offscreen inline edit, persistent close AX, selected state and vertical geometry passed; physical pointer/VoiceOver unverified")
    }
}
