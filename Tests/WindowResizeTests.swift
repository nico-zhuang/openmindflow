import AppKit

@main
enum WindowResizeTests {
    static func main() {
        let passed = run()
        if !passed { exit(1) } // Return through run first so its defer hides our own window.
    }

    private static func run() -> Bool {
        let suite = "local.mindmap.resize-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        let app = NSApplication.shared
        let delegate = AppDelegate(defaults: defaults)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification,
                                                              object: app)) // Own synthetic initial map only; no app.run.
        guard let window = app.windows.first(where: { $0.contentViewController is NSSplitViewController }),
              let split = window.contentViewController as? NSSplitViewController,
              let canvas = split.splitViewItems[1].viewController.view as? MapCanvas,
              let root = canvas.model.roots.first else {
            fputs("Synthetic AppDelegate did not create its own workbench window\n", stderr)
            for window in app.windows { window.orderOut(nil) }
            app.hide(nil)
            defaults.removePersistentDomain(forName: suite)
            return false
        }
        defer {
            window.orderOut(nil) // Never close: AppDelegate.windowShouldClose requests app termination.
            app.hide(nil)
            defaults.removePersistentDomain(forName: suite)
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let initial = window.frame
        let content = window.contentRect(forFrameRect: initial).size
        let outline = split.splitViewItems[0], inspector = split.splitViewItems[2]
        let collapsed = outline.isCollapsed && inspector.isCollapsed
        let increments = window.resizeIncrements
        let node = canvas.frameForAccessibility(root.id)!
        window.setFrame(CGRect(x: initial.minX, y: initial.minY + 50,
                               width: initial.width - 80, height: initial.height - 50), display: false)
        let resized = window.frame
        window.setFrame(initial, display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        let restored = window.frame
        let outlineItem = app.mainMenu!.item(withTitle: "View")!.submenu!.item(withTitle: "Show/Hide Outline")!
        let toolbar = window.toolbar!
        let styleButton = delegate.toolbar(toolbar, itemForItemIdentifier: NSToolbarItem.Identifier("style"),
                                           willBeInsertedIntoToolbar: true)!
        let outlineAction = app.sendAction(outlineItem.action!, to: outlineItem.target, from: outlineItem)
        window.contentView?.layoutSubtreeIfNeeded()
        let outlineFrame = window.frame
        let outlineNode = canvas.frameForAccessibility(root.id)!
        let styleAction = app.sendAction(styleButton.action!, to: styleButton.target, from: styleButton)
        window.contentView?.layoutSubtreeIfNeeded()
        let styleFrame = window.frame
        let styleNode = canvas.frameForAccessibility(root.id)!
        func stable(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.midX - b.midX) < 1 && abs(a.midY - b.midY) < 1
        }
        let passed = collapsed && content.width >= 1280 && content.height >= 700 &&
            window.styleMask.contains(.resizable) && window.minSize.width == 640 &&
            window.minSize.height >= 400 && window.minSize.height < initial.height &&
            increments == CGSize(width: 1, height: 1) && resized.width < initial.width &&
            resized.height < initial.height && restored == initial && outlineAction && styleAction &&
            outlineFrame == initial && styleFrame == initial && stable(node, outlineNode) && stable(node, styleNode)
        if !passed {
            fputs("Window check: collapsed=\(collapsed) initial=\(initial) content=\(content) min=\(window.minSize) increments=\(increments) resized=\(resized) restored=\(restored) outlineFrame=\(outlineFrame) styleFrame=\(styleFrame) node=\(node) outlineNode=\(outlineNode) styleNode=\(styleNode)\n", stderr)
        } else { print("own synthetic launch, resize, and pane geometry passed (not physical edge dragging)") }
        return passed
    }
}
