import AppKit
import Foundation
import Darwin

@main enum MultiDocumentCloseTests {
    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let defaults = UserDefaults(suiteName: "local.openmindflow.multi-close.\(UUID())")!
        let app = AppDelegate(defaults: defaults)
        let first = app.makeUnshownWindowSession()
        let second = app.makeUnshownWindowSession()
        let a = first.active!
        let c = second.active!
        let node = MapNode(id: UUID(), title: "B", children: [], folded: false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openmindflow-close-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
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
        // Closing a non-last document invalidates its Find and color ownership.
        first.confirmClose = { _ in true }
        assert(app.closeDocument(b, in: first))
        assert(first.documents.count == 1 && first.active === a && a.window === first.window)
        assert(b.window == nil && b.findWindow == nil && b.findField == nil && b.findMatches.isEmpty)
        assert(b.inspector.colorPanelModel == nil && app.windowSessions.count == 2)
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
        var confirmations: [DocumentSession] = []
        reopened.confirmClose = { doc in confirmations.append(doc); return true }
        assert(reopened.windowShouldClose(reopened.window))
        assert(confirmations.count == 2 && reopened.documents.count == 2)
        reopened.window.close()
        assert(!app.windowSessions.contains { $0 === reopened } && app.windowSessions.count == 1)
        assert(c.window === second.window && c.dirty && second.active === c)
        // A raw removal of the final member is intentionally not a close request (transfer seam).
        let transfer = app.makeUnshownWindowSession()
        let moving = transfer.active!
        transfer.remove(moving)
        assert(transfer.documents.isEmpty && transfer.active == nil && app.windowSessions.contains { $0 === transfer })
        assert(!transfer.window.isVisible && moving.window == nil)
        transfer.window.close()
        second.window.close()
        assert(app.windowSessions.isEmpty)
        print("Multi-document staged close, quit, refused editors and stale routing passed")
    }
}
