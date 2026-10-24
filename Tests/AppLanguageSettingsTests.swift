import AppKit

@main enum AppLanguageSettingsTests {
    static func main() {
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
        assert(NSApp.sendAction(settings.action!, to: settings.target, from: settings))
        popup.select(popup.itemArray.first { ($0.representedObject as? String) == "system" }!)
        assert(NSApp.sendAction(popup.action!, to: popup.target, from: popup))
        assert(L10n.choice(defaults: defaults) == "system")
        panel.orderOut(nil)
        window.orderOut(nil)
        print("native language setting, live Simplified Chinese UI, persistence and unchanged user content passed")
    }
}
