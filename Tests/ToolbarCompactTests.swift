import AppKit

@main
enum ToolbarCompactTests {
    static func main() {
        UserDefaults.standard.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        _ = NSApplication.shared // Offscreen; never launch/order/activate a user window.
        let delegate = AppDelegate()
        let toolbar = delegate.makeToolbar()
        assert(toolbar.displayMode == .iconOnly,
               "Native toolbar should keep controls compact while inspector has text-only tabs")
        let defaultIDs = delegate.toolbarDefaultItemIdentifiers(toolbar)
        let expected: [NSToolbarItem.Identifier] = [
            .init("outline"), .flexibleSpace,
            .init("new-main"), .init("new-child"), .init("new-sibling"),
            .init("fold-node"), .init("fit-map"), .flexibleSpace, .init("style")
        ]
        assert(defaultIDs == expected,
               "Default toolbar should expose seven grouped essentials, not duplicate Undo/Redo")
        let allowed = delegate.toolbarAllowedItemIdentifiers(toolbar)
        assert(defaultIDs.allSatisfy(allowed.contains) && allowed.contains(.init("undo")) &&
               allowed.contains(.init("redo")), "Undo/Redo should remain available for customization")
        for id in expected where id != .flexibleSpace {
            guard let item = delegate.toolbar(toolbar, itemForItemIdentifier: id,
                                              willBeInsertedIntoToolbar: true) else {
                fatalError("Missing toolbar item: \(id.rawValue)")
            }
            assert(item.image != nil && item.action != nil && item.target === delegate,
                   "Compact symbols must retain live native actions")
            assert(!item.label.isEmpty && item.toolTip == item.label,
                   "Icon-only toolbar must expose localized tooltips and accessible labels")
        }
        delegate.installMenu()
        guard let edit = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu else { fatalError("Missing Edit menu") }
        assert(edit.item(withTitle: "Undo")?.action != nil && edit.item(withTitle: "Redo")?.action != nil,
               "Removing Undo/Redo from default toolbar cannot remove keyboard/menu actions")
        print("compact native toolbar identities, actions and Edit menu passed (offscreen)")
    }
}
