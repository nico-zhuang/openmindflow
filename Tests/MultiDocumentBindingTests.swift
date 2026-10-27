import AppKit
import Darwin

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
        app.foregroundWindowForTesting = second.window
        _ = a.inspector.perform(NSSelectorFromString("changeCanvasPanelColor:"), with: panel)
        assert(a.canvas.model.canvasColor == beforeCanvas,
               "old A must reject color when C in another window is foreground")
        app.foregroundWindowForTesting = first.window
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
        app.foregroundWindowForTesting = second.window
        a.inspector.colorPanelModel = a.canvas.model
        _ = a.inspector.perform(NSSelectorFromString("changeCanvasPanelColor:"), with: panel)
        assert(a.canvas.model.canvasColor == beforeCanvas, "foreground C must reject A even while A remains active")
        a.canvas.armRelationshipColorPanelForTesting(edge.id)
        _ = a.canvas.perform(NSSelectorFromString("changeRelationshipPanelColor:"), with: panel)
        assert(a.canvas.model.relationships[0].color == previousColor,
               "foreground C must reject A's live relationship callback")
        app.foregroundWindowForTesting = first.window
        _ = a.inspector.perform(NSSelectorFromString("changeCanvasPanelColor:"), with: panel)
        let foregroundColor = a.canvas.model.canvasColor
        assert(foregroundColor != beforeCanvas,
               "foreground A must still accept its own color callback, as when shared panel is key")
        let temporaryParent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        precondition(temporaryParent.path.hasPrefix("/"))
        func privateDirectory(_ prefix: String) -> (URL, stat) {
            let directory = temporaryParent.appendingPathComponent("\(prefix)\(UUID())", isDirectory: true)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700])
            var identity = stat()
            precondition(lstat(directory.path, &identity) == 0 &&
                         directory.resolvingSymlinksInPath() == directory &&
                         directory.deletingLastPathComponent().resolvingSymlinksInPath() == temporaryParent &&
                         identity.st_uid == getuid() &&
                         identity.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
                         identity.st_mode & 0o777 == 0o700)
            return (directory, identity)
        }
        let (exportDirectory, ownedDirectory) = privateDirectory("mindmap-native-panel-")
        let (unadmittedDirectory, unadmittedIdentity) = privateDirectory("omf-binding-unadmitted-")
        try! "mindmap-owned-native-panel\n".write(to: exportDirectory.appendingPathComponent(".owner"),
                                                  atomically: true, encoding: .utf8)
        let previousPanelDirectory = getenv("MINDMAP_SELFTEST_PANEL_DIR").map { String(cString: $0) }
        precondition(setenv("MINDMAP_SELFTEST_PANEL_DIR", exportDirectory.path, 1) == 0)
        defer {
            if let previousPanelDirectory {
                precondition(setenv("MINDMAP_SELFTEST_PANEL_DIR", previousPanelDirectory, 1) == 0)
            } else {
                precondition(unsetenv("MINDMAP_SELFTEST_PANEL_DIR") == 0)
            }
            for (directory, identity) in [(exportDirectory, ownedDirectory),
                                          (unadmittedDirectory, unadmittedIdentity)] {
                var current = stat()
                if directory.path.hasPrefix("/") &&
                    directory.deletingLastPathComponent().resolvingSymlinksInPath() == temporaryParent &&
                    directory.resolvingSymlinksInPath() == directory &&
                    lstat(directory.path, &current) == 0 &&
                    current.st_dev == identity.st_dev && current.st_ino == identity.st_ino &&
                    current.st_uid == getuid() && current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
                    current.st_mode & 0o777 == 0o700 {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }
        let unadmittedURL = unadmittedDirectory.appendingPathComponent("existing.mflw")
        try! a.saveCurrentMap(to: unadmittedURL)
        var beforeUnadmitted = stat()
        precondition(lstat(unadmittedURL.path, &beforeUnadmitted) == 0)
        let originalUnadmittedBytes = try! Data(contentsOf: unadmittedURL)
        a.canvas.addMainNode()
        app.afterSavePanelForTesting = { captured in
            assert(captured === a, "hook must capture active A")
            return unadmittedURL
        }
        _ = app.perform(NSSelectorFromString("saveAsNative:"), with: nil)
        var afterUnadmitted = stat()
        assert(lstat(unadmittedURL.path, &afterUnadmitted) == 0 &&
               afterUnadmitted.st_dev == beforeUnadmitted.st_dev &&
               afterUnadmitted.st_ino == beforeUnadmitted.st_ino &&
               (try! Data(contentsOf: unadmittedURL)) == originalUnadmittedBytes,
               "post-panel hook must not authorize replacing an existing outside-fixture file")
        app.afterSavePanelForTesting = nil
        for action in ["saveAsNative:", "exportPDF:", "exportPNG:", "exportJPEG:",
                       "exportMarkdownFile:", "exportMindNodeCopy:"] {
            assert(first.activate(a))
            app.selectUnshownSessionForTesting(a)
            let suffix = action.replacingOccurrences(of: ":", with: "")
            let destination = exportDirectory.appendingPathComponent("\(suffix).\(action == "saveAsNative:" ? "mflw" : action == "exportMindNodeCopy:" ? "mindnode" : "pdf")")
            app.afterSavePanelForTesting = { captured in
                assert(captured === a, "panel must capture active A before opening")
                assert(first.activate(b))
                app.selectUnshownSessionForTesting(b)
                return destination
            }
            _ = app.perform(NSSelectorFromString(action), with: nil)
            assert(!FileManager.default.fileExists(atPath: destination.path),
                   "\(action) must not write after modal changes the active owner")
        }
        app.afterSavePanelForTesting = nil
        let nativeURL = exportDirectory.appendingPathComponent("explicit.mflw")
        try! a.saveCurrentMap(to: nativeURL)
        a.canvas.addMainNode()
        let pendingRoots = a.canvas.model.roots
        assert(first.activate(b))
        app.afterSavePanelForTesting = { _ in fatalError("existing file must not show a panel") }
        assert(app.saveExplicitSessionForTesting(a), "close confirmation may save live inactive A")
        assert((try! NativeMapFile.read(nativeURL)).document.roots == pendingRoots)
        var writes = 0
        app.beforeGuardedSaveWriteForTesting = { writes += 1 }
        app.afterSavePanelForTesting = { captured in
            assert(captured === a)
            first.remove(a)
            return exportDirectory.appendingPathComponent("detached.mflw")
        }
        assert(!app.saveExplicitSessionForTesting(a, chooseDestination: true) && writes == 0,
               "explicit session removed during modal must not write")
        app.afterSavePanelForTesting = nil
        assert(!app.saveExplicitSessionForTesting(a) && writes == 0,
               "already detached explicit session must not write")
        app.beforeGuardedSaveWriteForTesting = nil
        a.inspector.colorPanelModel = a.canvas.model
        panel.color = .systemBlue
        _ = a.inspector.perform(NSSelectorFromString("changeCanvasPanelColor:"), with: panel)
        assert(a.canvas.model.canvasColor == foregroundColor,
               "closed A cannot be recolored even with a stale model target")
        let bBeforeToolbar = b.canvas.model.roots
        first.newChild(nil)
        first.newMainNode(nil)
        assert(b.canvas.model.roots == bBeforeToolbar,
               "toolbar commands without sender must refuse non-key window")
        let toolbarItem = first.toolbar(toolbarA, itemForItemIdentifier: .init("new-main"),
                                        willBeInsertedIntoToolbar: true)!
        assert(NSApp.sendAction(toolbarItem.action!, to: toolbarItem.target, from: toolbarItem))
        assert(b.canvas.model.roots.count == bBeforeToolbar.count + 1,
               "explicit toolbar sender must route to its own non-key window")
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
