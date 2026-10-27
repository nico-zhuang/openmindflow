import AppKit
import Foundation

@main enum MultiWindowLifecycleTests {
    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let defaults = UserDefaults(suiteName: "local.openmindflow.windows.\(UUID())")!
        L10n.setLanguage("en", defaults: defaults)
        let app = AppDelegate(defaults: defaults)
        app.installMenu()
        let a = app.makeUnshownWindowSession()
        let b = app.makeUnshownWindowSession()
        assert(a !== b && a.window !== b.window)
        assert(a.documents.count == 1 && b.documents.count == 1)
        let first = a.active!, second = b.active!
        assert(first !== second && first.canvas !== second.canvas && first.canvas.model !== second.canvas.model)
        assert(first.canvas.onImageError != nil && first.canvas.onVideoError != nil &&
               second.canvas.onImageError != nil && second.canvas.onVideoError != nil)
        assert(first.fileURL == nil && second.fileURL == nil)
        assert(!a.window.isVisible && !b.window.isVisible && !a.window.isKeyWindow && !b.window.isKeyWindow)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("omf-windows-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("a.mflw")
        try first.saveCurrentMap(to: target)
        assert(first.fileURL == target && second.fileURL == nil)
        assert(first.canvas.model.roots[0].id != second.canvas.model.roots[0].id)
        second.canvas.addMainNode()
        assert(second.dirty && !first.dirty && first.fileURL == target)
        let savedRoots = try NativeMapFile.read(target).document.roots
        assert(savedRoots == first.canvas.model.roots)
        let toolbarA = a.window.toolbar!
        let toolbarB = b.window.toolbar!
        assert(toolbarA !== toolbarB && toolbarA.delegate as AnyObject? === a && toolbarB.delegate as AnyObject? === b)
        let newMainA = a.toolbar(toolbarA, itemForItemIdentifier: .init("new-main"), willBeInsertedIntoToolbar: true)!
        let newMainB = b.toolbar(toolbarB, itemForItemIdentifier: .init("new-main"), willBeInsertedIntoToolbar: true)!
        assert(newMainA.target as AnyObject? === a && newMainB.target as AnyObject? === b)
        let beforeA = first.canvas.model.roots.count, beforeB = second.canvas.model.roots.count
        assert(NSApp.sendAction(newMainB.action!, to: newMainB.target, from: newMainB))
        assert(first.canvas.model.roots.count == beforeA && second.canvas.model.roots.count == beforeB + 1)
        let sender = NSMenuItem(title: "New Window", action: NSSelectorFromString("newWindow:"), keyEquivalent: "n")
        sender.representedObject = a
        assert(NSApp.sendAction(sender.action!, to: app, from: sender))
        assert(app.windowSessions.count == 3)
        let c = app.windowSessions.last!
        assert(c !== a && c !== b && c.active!.canvas.model !== first.canvas.model && c.active!.canvas.model !== second.canvas.model)
        assert(!c.window.isVisible && !c.window.isKeyWindow)
        b.confirmClose = { _ in true }
        assert(b.window.delegate?.windowShouldClose?(b.window) == true)
        b.window.close()
        assert(!app.windowSessions.contains { $0 === b } && app.windowSessions.contains { $0 === a })
        assert(a.active === first && first.fileURL == target && !first.dirty)
        assert(!app.applicationShouldTerminateAfterLastWindowClosed(application))
        c.confirmClose = { _ in false }
        assert(app.applicationShouldTerminate(application) == .terminateCancel)
        assert(app.windowSessions.count == 2 && a.active === first && c.active != nil)
        c.confirmClose = { _ in true }
        assert(app.applicationShouldTerminate(application) == .terminateNow)
        c.window.close()
        a.window.close()
        assert(app.windowSessions.isEmpty)
        assert(NSApp.sendAction(sender.action!, to: app, from: sender))
        assert(app.windowSessions.count == 1 && app.windowSessions[0].active?.fileURL == nil)
        assert(!app.windowSessions[0].window.isVisible)
        print("independent unshown windows, toolbar routing, Command-N creation, per-window close and staged quit passed")
    }
}
