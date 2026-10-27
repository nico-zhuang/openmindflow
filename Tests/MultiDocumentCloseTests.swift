import AppKit
import Foundation
import Darwin

@main enum MultiDocumentCloseTests {
    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let defaults = UserDefaults(suiteName: "local.openmindflow.multi-close.\(UUID())")!
        let app = AppDelegate(defaults: defaults)
        let emptyOwner = app.makeUnshownWindowSession()
        let emptyDocument = emptyOwner.active!
        emptyOwner.remove(emptyDocument)
        assert(app.primarySessionForTesting == nil, "raw removal releases the former primary")
        app.cacheLegacySessionForTesting(emptyDocument, in: emptyOwner.window)
        assert(app.resolveSession(for: emptyOwner.window) == nil, "registered empty owner must never fall back")
        emptyOwner.window.close()
        let first = app.makeUnshownWindowSession()
        let second = app.makeUnshownWindowSession()
        let a = first.active!
        let c = second.active!
        let node = MapNode(id: UUID(), title: "B", children: [], folded: false)
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/openmindflow-close-XXXXXX").utf8CString
        let path = pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let created = mkdtemp(start) else { fatalError("mkdtemp failed") }
            return String(cString: created)
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        var owned = stat()
        precondition(lstat(directory.path, &owned) == 0 && owned.st_uid == getuid() &&
                     owned.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
                     owned.st_mode & 0o777 == 0o700 && directory.deletingLastPathComponent() == base)
        defer {
            var current = stat()
            if lstat(directory.path, &current) == 0 && current.st_dev == owned.st_dev &&
               current.st_ino == owned.st_ino && current.st_uid == getuid() &&
               current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
               current.st_mode & 0o777 == 0o700 { try? fm.removeItem(at: directory) }
        }
        let bURL = directory.appendingPathComponent("b.mflw")
        try NativeMapFile.write(.init(document: OwnMapDocument(roots: [node]), mindNodeArchive: nil), to: bURL)
        let b = try app.openMapInWindow(bURL, preferred: first)
        assert(first.documents.count == 2 && first.active === b)
        a.canvas.addMainNode()
        b.canvas.addMainNode()
        let aRoots = a.canvas.model.roots
        let bRoots = b.canvas.model.roots
        let bSelection = b.canvas.model.selectedIDs
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        panel.contentView?.addSubview(field)
        b.findWindow = panel
        b.findField = field
        b.findMatches = [node.id]
        b.findIndex = 0
        b.inspector.colorPanelModel = b.canvas.model
        func intact(_ name: String) {
            assert(app.windowSessions.count == 2 && app.windowSessions[0] === first && app.windowSessions[1] === second, "\(name): windows released")
            assert(first.documents.count == 2 && first.documents[0] === a && first.documents[1] === b && first.active === b, "\(name): document released")
            assert(second.documents.count == 1 && second.active === c, "\(name): other window changed")
            assert(a.window === first.window && b.window === first.window && c.window === second.window)
            assert(a.canvas.model.roots == aRoots && b.canvas.model.roots == bRoots && b.canvas.model.selectedIDs == bSelection)
            assert(b.findWindow === panel && b.findField === field && b.findMatches == [node.id])
            assert(b.inspector.colorPanelModel === b.canvas.model)
            assert(!first.window.isVisible && !second.window.isVisible)
        }
        let saveURL = directory.appendingPathComponent("a.mflw")
        var visited: [DocumentSession] = []
        first.confirmClose = { document in
            visited.append(document)
            if document === a { return (try? document.saveCurrentMap(to: saveURL)) != nil }
            return false
        }
        assert(!first.windowShouldClose(first.window))
        assert(visited.count == 2 && visited[0] === a && visited[1] === b)
        let savedA = try NativeMapFile.read(saveURL)
        assert(!a.dirty && b.dirty && savedA.document.roots == aRoots)
        intact("save then cancel")
        assert(app.applicationShouldTerminate(application) == .terminateCancel)
        intact("quit cancel")
        // Save failure after A was saved must not release either owner or any document.
        visited = []
        first.confirmClose = { document in
            visited.append(document)
            if document === b {
                setenv("MINDMAP_PANEL_ACTION", "save-failure", 1)
                defer { unsetenv("MINDMAP_PANEL_ACTION") }
                return (try? document.saveCurrentMap(to: bURL)) != nil
            }
            return true
        }
        assert(!first.prepareClose(documents: first.documents) && visited.count == 2)
        intact("save failure")
        assert(app.applicationShouldTerminate(application) == .terminateCancel)
        intact("quit save failure")
        // Confirmation must never bypass pending editor validation.
        b.inspector.noteTextView.string = String(repeating: "界", count: 22_000)
        assert(!b.commitPendingEditors())
        first.confirmClose = { _ in true }
        assert(!first.prepareClose(documents: first.documents))
        assert(!app.closeDocument(b, in: first))
        assert(app.applicationShouldTerminate(application) == .terminateCancel)
        intact("editor refusal")
        b.inspector.noteTextView.string = ""
        assert(b.commitPendingEditors())
        let edge = MapRelationship(from: node.id, to: bRoots.last!.id)
        assert(b.canvas.model.setRelationship(edge))
        b.canvas.armRelationshipColorPanelForTesting(edge.id)
        let panelColor = NSColorPanel.shared
        panelColor.color = .systemRed // Shared panel is never ordered or targeted in this test.
        c.canvas.addMainNode()
        let otherEdge = MapRelationship(from: c.canvas.model.roots[0].id, to: c.canvas.model.roots[1].id)
        assert(c.canvas.model.setRelationship(otherEdge))
        // Closing a non-last document invalidates its Find and color ownership.
        first.confirmClose = { _ in true }
        assert(app.closeDocument(b, in: first))
        assert(first.documents.count == 1 && first.active === a && a.window === first.window)
        assert(b.window == nil && b.findWindow == nil && b.findField == nil && b.findMatches.isEmpty)
        assert(b.inspector.colorPanelModel == nil && app.windowSessions.count == 2)
        let removedColor = b.canvas.model.relationships[0].color
        let otherColor = c.canvas.model.relationships[0].color
        _ = b.canvas.perform(NSSelectorFromString("changeRelationshipPanelColor:"), with: panelColor)
        assert(b.canvas.model.relationships[0].color == removedColor, "removed relationship callback edited B")
        assert(c.canvas.model.relationships[0].color == otherColor, "stale callback edited another document")
        assert(app.resolveSession(for: first.window) === a && app.resolveSession(for: second.window) === c)
        assert(!first.window.isVisible && !second.window.isVisible)
        let oldSelection = b.canvas.model.selectedIDs
        field.stringValue = "B"
        _ = app.perform(Selector(("findChanged:")), with: field)
        assert(b.canvas.model.selectedIDs == oldSelection && b.findMatches.isEmpty)
        let menuAction = NSMenuItem(title: "New child", action: Selector(("newChild:")), keyEquivalent: "")
        menuAction.target = app
        let bBefore = b.canvas.model.roots
        _ = app.perform(menuAction.action!, with: menuAction)
        assert(b.canvas.model.roots == bBefore, "stale menu route mutated a removed document")
        // Last document goes through native close; quit preflights all windows first.
        assert(app.closeDocument(a, in: first))
        assert(app.windowSessions.count == 1 && app.windowSessions[0] === second && a.window == nil)
        assert(app.primarySessionForTesting === c && app.resolveSession(for: first.window) == nil)
        second.confirmClose = { _ in true } // C gained an edge; never invoke a real modal prompt.
        assert(app.applicationShouldTerminate(application) == .terminateNow)
        let reopened = app.makeUnshownWindowSession()
        assert(app.windowSessions.count == 2 && reopened.active != nil && !reopened.window.isVisible)
        second.confirmClose = { _ in true }
        reopened.confirmClose = { _ in true }
        assert(app.applicationShouldTerminate(application) == .terminateNow)
        assert(app.windowSessions.count == 2, "quit preflight cannot release windows itself")
        // A later window rejecting quit cannot release an already-approved earlier window.
        c.canvas.addMainNode()
        second.confirmClose = { _ in false }
        assert(app.applicationShouldTerminate(application) == .terminateCancel)
        assert(app.windowSessions.count == 2 && reopened.active?.window === reopened.window && c.window === second.window)
        second.confirmClose = { _ in true }
        let d = try app.openMapInWindow(bURL, preferred: reopened)
        d.canvas.addMainNode()
        let closingEdge = MapRelationship(from: d.canvas.model.roots[0].id, to: d.canvas.model.roots[1].id)
        assert(d.canvas.model.setRelationship(closingEdge))
        d.canvas.armRelationshipColorPanelForTesting(closingEdge.id)
        var confirmations: [DocumentSession] = []
        reopened.confirmClose = { doc in confirmations.append(doc); return true }
        assert(reopened.windowShouldClose(reopened.window))
        assert(confirmations.count == 2 && reopened.documents.count == 2)
        reopened.window.close()
        let closedColor = d.canvas.model.relationships[0].color
        _ = d.canvas.perform(NSSelectorFromString("changeRelationshipPanelColor:"), with: panelColor)
        assert(d.canvas.model.relationships[0].color == closedColor, "closed window left a relationship callback armed")
        assert(!app.windowSessions.contains { $0 === reopened } && app.windowSessions.count == 1)
        assert(c.window === second.window && c.dirty && second.active === c)
        // A raw removal of the final member is intentionally not a close request (transfer seam).
        let transfer = app.makeUnshownWindowSession()
        let moving = transfer.active!
        transfer.remove(moving)
        assert(transfer.documents.isEmpty && transfer.active == nil && app.windowSessions.contains { $0 === transfer })
        assert(app.resolveSession(for: transfer.window) == nil, "registered empty owner must not use stale cached session")
        assert(!transfer.window.isVisible && moving.window == nil)
        let legacyApp = AppDelegate(defaults: defaults)
        let legacy = legacyApp.installAdditionalUnshownDocumentFixture(canvas: MapCanvas(model: MapModel(roots: [node], selected: node.id)))
        assert(legacyApp.resolveSession(for: legacy.window) === legacy.session,
               "unregistered legacy fixture retains its routing")
        assert(legacyApp.primarySessionForTesting === legacy.session)
        transfer.window.close()
        second.window.close()
        assert(app.windowSessions.isEmpty)
        print("Multi-document staged close, quit, refused editors and stale routing passed")
    }
}
