import AppKit

@main enum MultiDocumentBindingTests {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let name = "local.openmindflow.binding.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        assert(L10n.setLanguage("en", defaults: defaults))
        let app = AppDelegate(defaults: defaults)
        let first = app.makeUnshownWindowSession()
        let second = app.makeUnshownWindowSession()
        let a = first.active!
        let c = second.active!
        let b = DocumentSession(canvas: MapCanvas(model: MapModel(roots: [
            MapNode(id: UUID(), title: "B", children: [], folded: false)
        ], selected: UUID())), defaults: defaults)
        first.insert(b)
        assert(first.activate(b))
        assert(first.activate(a))
        assert(first.window.title.contains("Untitled") && second.window.title.contains("Untitled"))
        let findA = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let findC = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let fieldA = NSSearchField(), fieldC = NSSearchField()
        let statusA = NSTextField(labelWithString: "No matches")
        let statusC = NSTextField(labelWithString: "No matches")
        a.findWindow = findA; a.findField = fieldA; a.findStatus = statusA
        c.findWindow = findC; c.findField = fieldC; c.findStatus = statusC
        let toolbarA = first.window.toolbar!, toolbarC = second.window.toolbar!
        assert(toolbarA.items.contains { $0.itemIdentifier.rawValue == "new-main" } &&
               toolbarC.items.contains { $0.itemIdentifier.rawValue == "new-main" })
        app.selectUnshownSessionForTesting(a)
        app.installMenu()
        _ = app.perform(NSSelectorFromString("showSettings:"), with: nil)
        let settings = NSApp.windows.first { $0.title == "Settings" }!
        assert(app.resolveSession(for: settings) == nil,
               "an explicit settings owner must not inherit a headless document anchor")
        let language = settings.contentView!.subviews.compactMap { $0 as? NSPopUpButton }
            .first { $0.identifier?.rawValue == "general-language" }!
        language.select(language.itemArray.first { $0.representedObject as? String == "zh-Hans" })
        _ = app.perform(NSSelectorFromString("chooseLanguage:"), with: language)
        let translated = L10n.text("Untitled", defaults: defaults)
        assert(first.window.title.contains(translated) && second.window.title.contains(translated),
               "language must update all registered active titles")
        assert(findA.title == L10n.text("Find", defaults: defaults) &&
               findC.title == L10n.text("Find", defaults: defaults) &&
               statusA.stringValue == L10n.text("No matches", defaults: defaults) &&
               statusC.stringValue == L10n.text("No matches", defaults: defaults),
               "language must update each document Find panel")
        assert(a.inspector.familyPopup.accessibilityLabel() == L10n.text("Font family", defaults: defaults) ||
               a.inspector.familyPopup.accessibilityLabel() == "字体名称")
        assert(c.inspector.familyPopup.accessibilityLabel() == a.inspector.familyPopup.accessibilityLabel(),
               "both workbenches must localize")
        let mainA = toolbarA.items.first { $0.itemIdentifier.rawValue == "new-main" }
        let mainC = toolbarC.items.first { $0.itemIdentifier.rawValue == "new-main" }
        assert(mainA?.label == mainC?.label &&
               mainA?.label == L10n.text("New Main Node", defaults: defaults),
               "every toolbar must localize")
        let titleBefore = first.window.title
        b.canvas.addMainNode()
        assert(first.window.title == titleBefore, "inactive dirty metadata must not replace active title")

        a.inspector.colorPanelModel = a.canvas.model
        let panel = NSColorPanel.shared // Never order the shared panel.
        panel.color = .systemRed
        let beforeCanvas = a.canvas.model.canvasColor
        let beforeRoots = a.canvas.model.roots
        assert(first.activate(b))
        _ = a.inspector.perform(NSSelectorFromString("changeCanvasPanelColor:"), with: panel)
        _ = a.inspector.perform(NSSelectorFromString("changeRootPanelColor:"), with: panel)
        _ = a.inspector.perform(NSSelectorFromString("changeStrokeColor:"), with: panel)
        assert(a.canvas.model.canvasColor == beforeCanvas && a.canvas.model.roots == beforeRoots,
               "inactive inspector callback must not edit A")
        assert(b.canvas.model.canvasColor == nil, "inactive inspector callback must not edit B")
        let rootID = a.canvas.model.roots[0].id
        a.canvas.addMainNode()
        let edge = MapRelationship(from: rootID, to: a.canvas.model.roots.last!.id)
        assert(a.canvas.model.setRelationship(edge))
        a.canvas.armRelationshipColorPanelForTesting(edge.id)
        let previousColor = a.canvas.model.relationships[0].color
        _ = a.canvas.perform(NSSelectorFromString("changeRelationshipPanelColor:"), with: panel)
        assert(a.canvas.model.relationships[0].color == previousColor,
               "inactive relationship callback must not edit A")
        assert(first.activate(a))
        first.remove(a)
        let bBeforeToolbar = b.canvas.model.roots
        first.newChild(nil)
        first.newMainNode(nil)
        assert(b.canvas.model.roots == bBeforeToolbar,
               "toolbar commands must refuse a window that is not key")
        _ = a.canvas.perform(NSSelectorFromString("changeRelationshipPanelColor:"), with: panel)
        assert(a.canvas.model.relationships[0].color == previousColor,
               "removed relationship callback must not edit A")
        let noOwner = AppDelegate(defaults: defaults)
        for action in ["newChild:", "insertImageFile:", "insertVideoFile:", "saveFile:",
                       "saveAsNative:", "exportPDF:", "exportPNG:", "exportJPEG:",
                       "exportMarkdownFile:", "exportMindNodeCopy:"] {
            _ = noOwner.perform(NSSelectorFromString(action), with: nil)
        }
        let orphanToolbar = noOwner.makeToolbar()
        for identifier in noOwner.toolbarDefaultItemIdentifiers(orphanToolbar) {
            if let item = noOwner.toolbar(orphanToolbar, itemForItemIdentifier: identifier,
                                          willBeInsertedIntoToolbar: true), let action = item.action {
                _ = item.target?.perform(action, with: item)
            }
        }
        assert(!first.window.isVisible && !second.window.isVisible && !settings.isVisible && !panel.isVisible,
               "synthetic fixtures must never order windows or panels")
        first.window.close(); second.window.close()
        print("Multi-document language, live color callback and document-bound commands passed")
    }
}
