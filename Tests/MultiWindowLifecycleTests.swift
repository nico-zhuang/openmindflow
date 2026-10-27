import AppKit
import Foundation
import Darwin

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
        var ownedDirectory = stat()
        precondition(lstat(directory.path, &ownedDirectory) == 0 &&
                     ownedDirectory.st_uid == getuid() &&
                     ownedDirectory.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
                     ownedDirectory.st_mode & 0o777 == 0o700)
        defer {
            var current = stat()
            if lstat(directory.path, &current) == 0 &&
               current.st_dev == ownedDirectory.st_dev && current.st_ino == ownedDirectory.st_ino &&
               current.st_uid == getuid() && current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
               current.st_mode & 0o777 == 0o700 {
                try? FileManager.default.removeItem(at: directory)
            }
        }
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
        assert(app.windowSessions.contains { $0 === b } && app.windowSessions.contains { $0 === a })
        assert(a.active === first && first.fileURL == target && !first.dirty)
        assert(!app.applicationShouldTerminateAfterLastWindowClosed(application))
        c.confirmClose = { _ in false }
        assert(app.applicationShouldTerminate(application) == .terminateCancel)
        assert(app.windowSessions.count == 3 && a.active === first && c.active != nil)
        c.confirmClose = { _ in true }
        assert(app.applicationShouldTerminate(application) == .terminateNow)
        c.window.close()
        // A Find panel is never ordered: callbacks from its controls must not search B
        // after A closes, even when B is still registered.
        let findPanel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 430, height: 110),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let findField = NSSearchField(frame: CGRect(x: 16, y: 58, width: 398, height: 28))
        findField.target = app
        findField.action = NSSelectorFromString("findChanged:")
        findField.stringValue = first.canvas.model.roots[0].title
        findPanel.contentView?.addSubview(findField)
        let next = NSButton(title: "Next", target: app, action: NSSelectorFromString("findNext:"))
        findPanel.contentView?.addSubview(next)
        first.findWindow = findPanel
        first.findField = findField
        first.findStatus = NSTextField(labelWithString: "No matches")
        let bSelection = second.canvas.model.selected
        assert(NSApp.sendAction(findField.action!, to: findField.target, from: findField))
        assert(first.findMatches.count == 1 && second.findMatches.isEmpty && second.canvas.model.selected == bSelection,
               "A's Find callback must search A, not B")
        a.window.close()
        assert(first.window == nil && first.findWindow == nil && first.findField == nil,
               "Closing A must detach its Find panel and controls")
        assert(!findPanel.isVisible && app.windowSessions.count == 1 && app.windowSessions[0] === b)
        assert(NSApp.sendAction(findField.action!, to: findField.target, from: findField))
        assert(NSApp.sendAction(next.action!, to: next.target, from: next))
        assert(first.findMatches.isEmpty && second.findMatches.isEmpty &&
               second.canvas.model.selected == bSelection && first.canvas.model.selected == first.canvas.model.roots[0].id,
               "Stale Find and Next must not search a closed document or route to another document")
        b.window.close()
        assert(app.windowSessions.isEmpty)
        let closedRoots = first.canvas.model.roots
        let closedBRoots = second.canvas.model.roots
        let savedBytes = try Data(contentsOf: target)
        let nodeMenu = NSApp.mainMenu!.item(withTitle: "Node")!.submenu!
        for title in ["New Main Node", "New Child", "New Sibling", "Detach Node"] {
            let item = nodeMenu.item(withTitle: title)!
            assert(NSApp.sendAction(item.action!, to: item.target, from: item))
        }
        let saveItem = NSApp.mainMenu!.item(withTitle: "File")!.submenu!.item(withTitle: "Save")!
        var beforeSaveFile = stat()
        assert(lstat(target.path, &beforeSaveFile) == 0)
        assert(NSApp.sendAction(saveItem.action!, to: saveItem.target, from: saveItem))
        var afterSaveFile = stat()
        assert(lstat(target.path, &afterSaveFile) == 0)
        let afterSaveBytes = try Data(contentsOf: target)
        assert(first.canvas.model.roots == closedRoots && second.canvas.model.roots == closedBRoots &&
               afterSaveBytes == savedBytes,
               "Node actions and Save must not change closed documents or saved bytes")
        assert(afterSaveFile.st_dev == beforeSaveFile.st_dev && afterSaveFile.st_ino == beforeSaveFile.st_ino,
               "Final-window Save must not replace the saved file with identical bytes")
        assert(NSApp.sendAction(sender.action!, to: app, from: sender))
        assert(app.windowSessions.count == 1 && app.windowSessions[0].active?.fileURL == nil)
        assert(!app.windowSessions[0].window.isVisible)
        print("independent unshown windows, toolbar routing, Command-N creation, per-window close and staged quit passed")
    }
}
