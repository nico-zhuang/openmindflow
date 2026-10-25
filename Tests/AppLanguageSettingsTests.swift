import AppKit

@main enum AppLanguageSettingsTests {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited) // Offscreen tests never activate the user's desktop.
        let suite = "local.mindmap.language-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        assert(L10n.setLanguage("en", defaults: defaults))
        let node = MapNode(id: UUID(), title: "Do not translate user content", children: [], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [node], selected: node.id))
        let delegate = AppDelegate(defaults: defaults)
        let workbench = delegate.makeWorkbench(canvas: canvas)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = workbench
        delegate.installMenu()
        let settings = NSApp.mainMenu!.items[0].submenu!.item(withTitle: "Settings…")!
        assert(NSApp.sendAction(settings.action!, to: settings.target, from: settings))
        guard let panel = NSApp.windows.first(where: { $0.title == "Settings" }),
              let popup = panel.contentView?.subviews.compactMap({ $0 as? NSPopUpButton }).first,
              popup.itemArray.contains(where: { ($0.representedObject as? String) == "zh-Hans" }) else {
            fatalError("Native Settings must offer system/Chinese/English app language")
        }
        let tabs = panel.contentView!.subviews.compactMap { $0 as? NSSegmentedControl }.first
        let appearancePopup = panel.contentView!.subviews.compactMap { $0 as? NSPopUpButton }
            .first { $0.accessibilityLabel() == "Appearance" }
        let shrink = panel.contentView!.subviews.compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Shrink new nodes to fit content" }
        guard let tabs, tabs.segmentCount == 2,
              tabs.label(forSegment: 0) == "General",
              tabs.label(forSegment: 1) == "Keyboard Shortcuts",
              let appearancePopup, appearancePopup.itemTitles == ["System", "Light", "Dark"],
              let shrink, shrink.state == .on,
              !panel.contentView!.subviews.compactMap({ ($0 as? NSControl)?.accessibilityLabel() })
                .contains(where: { ["License", "Account", "Dock Icon"].contains($0) }) else {
            fputs("RED Settings must expose only General/Keyboard Shortcuts and real language/appearance/compact-width options\n", stderr)
            exit(1)
        }
        let languageLabel = panel.contentView!.subviews.compactMap { $0 as? NSTextField }.first!
        assert(languageLabel.intrinsicContentSize.width <= languageLabel.frame.width &&
               languageLabel.frame.maxX <= popup.frame.minX,
               "Settings language label must fit and not collide with native popup")
        popup.select(popup.itemArray.first { ($0.representedObject as? String) == "zh-Hans" }!)
        assert(NSApp.sendAction(popup.action!, to: popup.target, from: popup))
        assert(L10n.choice(defaults: defaults) == "zh-Hans")
        assert(NSApp.mainMenu?.item(withTitle: "文件") != nil &&
               NSApp.mainMenu?.item(withTitle: "视图") != nil &&
               canvas.model.roots == [node],
               "Language changes UI immediately without translating or discarding the map")
        let inspector = workbench.splitViewItems[2].viewController.view as! StyleInspector
        assert(inspector.familyPopup.accessibilityLabel() == "字体名称")
        let appearance = NSApp.mainMenu!.item(withTitle: "视图")!.submenu!
            .item(withTitle: "外观")!.submenu!
        let dark = appearance.item(withTitle: "深色")!
        assert(NSApp.sendAction(dark.action!, to: dark.target, from: dark) &&
               defaults.string(forKey: "appearance") == "dark" &&
               NSApp.appearance?.name == .darkAqua,
               "Translated menu title must not change the stable appearance command")
        assert(appearancePopup.selectedItem?.representedObject as? String == "dark",
               "Appearance menu edits must synchronize the open General popup")
        appearancePopup.select(appearancePopup.itemArray.first { ($0.representedObject as? String) == "light" }!)
        assert(NSApp.sendAction(appearancePopup.action!, to: appearancePopup.target, from: appearancePopup))
        assert(defaults.string(forKey: "appearance") == "light" && NSApp.appearance?.name == .aqua &&
               appearance.item(withTitle: "浅色")?.state == .on,
               "General appearance must persist, apply immediately, and check the existing View menu")
        shrink.state = .off
        assert(NSApp.sendAction(shrink.action!, to: shrink.target, from: shrink))
        assert(defaults.bool(forKey: "shrinkNewNodesToFitContent") == false)
        canvas.addChild()
        let wideField = canvas.subviews.compactMap { $0 as? NSTextField }.first!
        wideField.stringValue = "Wide default"
        canvas.commitEditing()
        assert(canvas.model.roots[0].children[0].width == nil &&
               mapLayout(canvas.model.roots).first(where: { $0.node.id == canvas.model.selected })!.frame.width == 170,
               "Disabling shrink must retain the default 170pt first-title width")
        shrink.state = .on
        assert(NSApp.sendAction(shrink.action!, to: shrink.target, from: shrink))
        canvas.addChild()
        let compactField = canvas.subviews.compactMap { $0 as? NSTextField }.first!
        compactField.stringValue = "Small"
        canvas.commitEditing()
        assert((canvas.model.roots[0].children[0].children[0].width ?? 170) < 170,
               "Default-on shrink must measure a compact first-title width")
        assert(NSApp.sendAction(settings.action!, to: settings.target, from: settings))
        popup.select(popup.itemArray.first { ($0.representedObject as? String) == "system" }!)
        assert(NSApp.sendAction(popup.action!, to: popup.target, from: popup))
        assert(L10n.choice(defaults: defaults) == "system" &&
               defaults.string(forKey: "appearance") == "light" &&
               appearancePopup.selectedItem?.representedObject as? String == "light",
               "Language changes must retain General appearance and compact-width preferences")
        tabs.selectedSegment = 1
        assert(NSApp.sendAction(tabs.action!, to: tabs.target, from: tabs))
        let bindings = [("new-child", "tab"), ("new-sibling", "return"),
                        ("new-sibling-before", "option-return"), ("new-main", "shift-return"),
                        ("new-parent", "option-tab"), ("edit-title", "command-return")]
        let shortcutPopups = panel.contentView!.subviews.compactMap { $0 as? NSPopUpButton }
            .filter { $0.identifier?.rawValue.hasPrefix("shortcuts-") == true }
        let restore = panel.contentView!.subviews.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "shortcuts-restore" }
        guard shortcutPopups.count == 6, let restore, !restore.isHidden,
              popup.isHidden, appearancePopup.isHidden, shrink.isHidden,
              bindings.allSatisfy({ name, key in
                  shortcutPopups.first(where: { $0.identifier?.rawValue == "shortcuts-\(name)" })
                    .map { !$0.isHidden && $0.numberOfItems == 12 &&
                           ($0.selectedItem?.representedObject as? String) == key } == true
              }) else {
            fputs("RED Shortcut page must show six editable persisted node commands and Restore Defaults\n", stderr)
            exit(1)
        }
        let childPopup = shortcutPopups.first { $0.identifier?.rawValue == "shortcuts-new-child" }!
        let parentPopup = shortcutPopups.first { $0.identifier?.rawValue == "shortcuts-new-parent" }!
        childPopup.select(childPopup.itemArray.first { ($0.representedObject as? String) == "control-tab" }!)
        assert(NSApp.sendAction(childPopup.action!, to: childPopup.target, from: childPopup))
        assert((defaults.dictionary(forKey: "nodeShortcuts") as? [String: String])?["new-child"] == "control-tab" &&
               (UserDefaults(suiteName: suite)!.dictionary(forKey: "nodeShortcuts") as? [String: String])?["new-child"] == "control-tab",
               "Changed shortcut must persist across defaults instances")
        parentPopup.select(parentPopup.itemArray.first { ($0.representedObject as? String) == "control-tab" }!)
        assert(NSApp.sendAction(parentPopup.action!, to: parentPopup.target, from: parentPopup))
        assert(parentPopup.selectedItem?.representedObject as? String == "option-tab" &&
               (defaults.dictionary(forKey: "nodeShortcuts") as? [String: String])?["new-parent"] == "option-tab",
               "Duplicate node shortcuts must be rejected in UI and persisted settings")
        let nodeMenu = NSApp.mainMenu!.item(withTitle: L10n.text("Node", defaults: defaults))!.submenu!
        let childItem = nodeMenu.item(withTitle: L10n.text("New Child", defaults: defaults))!
        guard childItem.keyEquivalent == "\t", childItem.keyEquivalentModifierMask == [.control] else {
            fputs("RED Node menu must mirror live shortcut changes without a stale Tab binding\n", stderr)
            exit(1)
        }
        func tab(_ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "\t",
                charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
        }
        let rootsBeforeShortcut = canvas.model.roots
        canvas.keyDown(with: tab())
        assert(canvas.model.roots == rootsBeforeShortcut, "Reassigned Tab must stop adding children")
        canvas.keyDown(with: tab(.control))
        let newlySelected = canvas.model.selected
        assert(canvas.model.roots != rootsBeforeShortcut &&
               canvas.subviews.contains(where: { $0 is NSTextField }),
               "Control-Tab must really add a child and open its editor after remapping")
        canvas.subviews.compactMap { $0 as? NSTextField }.first!.stringValue = "Typed before child"
        NSApp.postEvent(tab(.control), atStart: true)
        _ = NSApp.nextEvent(matching: .keyDown, until: Date().addingTimeInterval(0.1),
                            inMode: .default, dequeue: true)
        assert(canvas.control(NSTextField(), textView: NSTextView(),
                              doCommandBy: #selector(NSResponder.insertTabIgnoringFieldEditor(_:))))
        assert(canvas.model.selected != newlySelected &&
               canvas.model.roots != rootsBeforeShortcut &&
               canvas.subviews.contains(where: { $0 is NSTextField }),
               "The same changed shortcut must commit the active editor then create a child")
        let editPopup = shortcutPopups.first { $0.identifier?.rawValue == "shortcuts-edit-title" }!
        editPopup.select(editPopup.itemArray.first { ($0.representedObject as? String) == "control-return" }!)
        assert(NSApp.sendAction(editPopup.action!, to: editPopup.target, from: editPopup))
        let editRoot = MapNode(id: UUID(), title: "Editable", children: [], folded: false)
        let editCanvas = MapCanvas(model: MapModel(roots: [editRoot], selected: editRoot.id))
        editCanvas.localizationDefaults = defaults
        editCanvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .control, timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        assert(editCanvas.subviews.contains(where: { $0 is NSTextField }),
               "Remapped Edit Title must open the actual native node text editor")
        tabs.selectedSegment = 0
        assert(NSApp.sendAction(tabs.action!, to: tabs.target, from: tabs))
        popup.select(popup.itemArray.first { ($0.representedObject as? String) == "zh-Hans" }!)
        assert(NSApp.sendAction(popup.action!, to: popup.target, from: popup))
        tabs.selectedSegment = 1
        assert(NSApp.sendAction(tabs.action!, to: tabs.target, from: tabs))
        assert(tabs.label(forSegment: 1) == "快捷键" &&
               childPopup.item(withTitle: "Control + Tab 键")?.representedObject as? String == "control-tab" &&
               editPopup.selectedItem?.representedObject as? String == "control-return" &&
               defaults.string(forKey: "appearance") == "light",
               "Language switching must relabel real shortcuts without resetting their bindings or appearance")
        let beforeRestore = canvas.model.roots
        assert(NSApp.sendAction(restore.action!, to: restore.target, from: restore) &&
               defaults.object(forKey: "nodeShortcuts") == nil &&
               childPopup.selectedItem?.representedObject as? String == "tab")
        canvas.commitEditing()
        canvas.keyDown(with: tab())
        assert(canvas.model.roots != beforeRestore,
               "Restore Defaults must make Tab create a child again")
        panel.orderOut(nil)
        window.orderOut(nil)
        print("native General appearance/width, live language and editable unique node shortcuts passed")
    }
}
