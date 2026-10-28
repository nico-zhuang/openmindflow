import AppKit
import Foundation
import Darwin
import CryptoKit

@main enum TabTitlePersistenceTests {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let defaults = UserDefaults(suiteName: "local.openmindflow.tab-title.\(UUID())")!
        L10n.setLanguage("en", defaults: defaults)
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var template = (base.path + "/openmindflow-tab-title-XXXXXX").utf8CString
        let path = try template.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let made = mkdtemp(start) else { throw POSIXError(.EIO) }
            return String(cString: made)
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        var owner = stat()
        precondition(folder.deletingLastPathComponent() == base &&
                     folder.resolvingSymlinksInPath().standardizedFileURL == folder &&
                     lstat(path, &owner) == 0 && owner.st_uid == getuid() &&
                     owner.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) && owner.st_mode & 0o777 == 0o700)
        defer {
            var now = stat()
            if lstat(path, &now) == 0 && now.st_dev == owner.st_dev && now.st_ino == owner.st_ino &&
               now.st_uid == getuid() && now.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
               now.st_mode & 0o777 == 0o700 && folder.deletingLastPathComponent() == base {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        let root = MapNode(id: UUID(), title: "Map root stays", children: [], folded: false)
        let document = OwnMapDocument(roots: [root])
        let app = AppDelegate(defaults: defaults)
        let firstOwner = app.makeUnshownWindowSession(), secondOwner = app.makeUnshownWindowSession()
        let first = firstOwner.active!, second = secondOwner.active!
        assert(first.displayTabTitle(defaults: defaults) == "Untitled")
        assert(first.renameTab(to: "  Cafe\u{301}  "))
        assert(first.tabTitleOverride == "Café" && first.dirty)
        assert(firstOwner.window.title.contains("Café •") && !secondOwner.window.title.contains("Café"))
        for invalid in ["", " \n ", "a\u{0}b", "bad\u{7F}name", "a\nb", String(repeating: "a", count: 129), String(repeating: "界", count: 86)] {
            assert(!first.renameTab(to: invalid), "Must reject unsafe title: \(invalid.debugDescription)")
            assert(first.tabTitleOverride == "Café" && first.dirty)
        }
        assert(second.renameTab(to: "Second"))
        assert(secondOwner.window.title.contains("Second") && firstOwner.window.title.contains("Café"))
        let source = folder.appendingPathComponent("Original-File.mflw")
        try NativeMapFile.write(.init(document: document, mindNodeArchive: nil), to: source)
        let old = try NativeMapFile.read(source)
        assert(old.tabTitle == nil, "Legacy optional title must decode as nil")
        first.installDocument(try first.preflightMap(at: source))
        assert(first.tabTitleOverride == nil && !first.dirty)
        assert(first.displayTabTitle(defaults: defaults) == "Original-File.mflw")
        let sourceBytes = try Data(contentsOf: source)
        assert(first.renameTab(to: "Visible Only"))
        assert(first.fileURL == source && first.canvas.model.roots == document.roots)
        let afterRenameBytes = try Data(contentsOf: source)
        assert(afterRenameBytes == sourceBytes, "Rename cannot silently write or move a file")
        assert(FileManager.default.fileExists(atPath: source.path))
        assert(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Visible Only.mflw").path))
        try first.saveCurrentMap(to: source)
        assert(!first.dirty && first.tabTitleOverride == "Visible Only")
        let savedTitle = try NativeMapFile.read(source).tabTitle
        assert(savedTitle == "Visible Only")
        first.canvas.addMainNode()
        first.canvas.undo()
        assert(first.tabTitleOverride == "Visible Only" && !first.dirty)
        assert(first.canvas.model.roots == document.roots)
        let transfer = DocumentTabTransfer()
        let token = transfer.begin(document: first, source: firstOwner)
        assert(transfer.move(token: token, to: secondOwner, insertion: 0))
        assert(first.window === secondOwner.window && secondOwner.active === first)
        assert(first.tabTitleOverride == "Visible Only" && second.tabTitleOverride == "Second")
        assert(secondOwner.window.title.contains("Visible Only") && firstOwner.documents.isEmpty)
        assert(secondOwner.activate(second))
        let inactiveTitle = secondOwner.window.title
        assert(first.renameTab(to: "Inactive Only"))
        assert(secondOwner.window.title == inactiveTitle, "Inactive title callback cannot overwrite active window title")
        assert(secondOwner.activate(first) && secondOwner.window.title.contains("Inactive Only"))
        let savedAs = folder.appendingPathComponent("Separate-Name.mflw")
        try first.saveCurrentMap(to: savedAs)
        let reopened = DocumentSession(canvas: MapCanvas(model: MapModel(roots: [root], selected: root.id)), defaults: defaults)
        reopened.installDocument(try reopened.preflightMap(at: savedAs))
        assert(reopened.tabTitleOverride == "Inactive Only" && !reopened.dirty)
        assert(reopened.displayTabTitle(defaults: defaults) == "Inactive Only")
        assert(reopened.canvas.model.roots == document.roots && reopened.mindNodeArchive == nil)
        let legacy = folder.appendingPathComponent("legacy.mindmap.json")
        try writeOwnDocument(document, to: legacy)
        reopened.installDocument(try reopened.preflightMap(at: legacy))
        assert(reopened.tabTitleOverride == nil && reopened.displayTabTitle(defaults: defaults) == "Untitled")
        print("tab title validation, optional native metadata, save/reopen, callback isolation, and transfer passed")
    }
}
