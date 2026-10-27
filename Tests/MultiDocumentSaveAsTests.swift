import AppKit
import Foundation
import Darwin

@main enum MultiDocumentSaveAsTests {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/openmindflow-save-as-XXXXXX").utf8CString
        let path = pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let created = mkdtemp(start) else { fatalError("mkdtemp failed") }
            return String(cString: created)
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        var owned = stat()
        precondition(directory.path == directory.standardizedFileURL.path &&
                     directory.deletingLastPathComponent() == base &&
                     lstat(directory.path, &owned) == 0 && owned.st_uid == getuid() &&
                     owned.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
                     owned.st_mode & 0o777 == 0o700)
        defer {
            var current = stat()
            if lstat(directory.path, &current) == 0 && current.st_dev == owned.st_dev &&
               current.st_ino == owned.st_ino && current.st_uid == getuid() &&
               current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) &&
               current.st_mode & 0o777 == 0o700 && directory.deletingLastPathComponent() == base {
                try? fm.removeItem(at: directory)
            }
        }
        func identity(_ url: URL) -> NativeMapFile.FileIdentity {
            var info = stat()
            precondition(url.path == url.standardizedFileURL.path && url.deletingLastPathComponent() == directory &&
                         lstat(url.path, &info) == 0 && info.st_uid == getuid() &&
                         info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG))
            return .init(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
        }
        let aURL = directory.appendingPathComponent("a.mflw")
        let bURL = directory.appendingPathComponent("b.mflw")
        let alias = directory.appendingPathComponent("b-alias.mflw")
        let aNode = MapNode(id: UUID(), title: "A", children: [], folded: false)
        let bNode = MapNode(id: UUID(), title: "B", children: [], folded: false)
        try NativeMapFile.write(.init(document: OwnMapDocument(roots: [aNode]), mindNodeArchive: nil), to: aURL)
        try NativeMapFile.write(.init(document: OwnMapDocument(roots: [bNode]), mindNodeArchive: nil), to: bURL)
        try fm.linkItem(at: bURL, to: alias)
        let app = AppDelegate(defaults: UserDefaults(suiteName: "local.openmindflow.save-as.\(UUID())")!)
        let first = app.makeUnshownWindowSession()
        let second = app.makeUnshownWindowSession()
        let a = try app.openMapInWindow(aURL, preferred: first)
        let b = try app.openMapInWindow(bURL, preferred: second)
        app.selectUnshownSessionForTesting(a)
        a.canvas.addMainNode()
        let roots = a.canvas.model.roots
        let original = try Data(contentsOf: bURL)
        let originalID = identity(bURL)
        for target in [bURL, alias] {
            do { try app.saveCurrentMap(to: target); fatalError("Save As must reject B's \(target.lastPathComponent)") }
            catch NativeMapFile.FileError.conflict { }
            let bBytes = try Data(contentsOf: bURL)
            let aliasBytes = try Data(contentsOf: alias)
            assert(bBytes == original && identity(bURL) == originalID)
            assert(aliasBytes == original && identity(alias) == originalID)
            assert(a.fileURL == aURL && a.dirty && a.canvas.model.roots == roots)
            assert(b.fileURL == bURL && b.canvas.model.roots == [bNode] && !b.dirty)
        }
        let swap = directory.appendingPathComponent("swap.mflw")
        let parked = directory.appendingPathComponent("parked.mflw")
        let replacement = directory.appendingPathComponent("replacement.mflw")
        try NativeMapFile.write(.init(document: OwnMapDocument(roots: [aNode]), mindNodeArchive: nil), to: swap)
        let sameBytes = try Data(contentsOf: swap)
        try sameBytes.write(to: replacement, options: .withoutOverwriting)
        let replacedBytes = try Data(contentsOf: replacement)
        let replacedID = identity(replacement)
        let originalSwapID = identity(swap)
        assert(replacedBytes == sameBytes && replacedID != originalSwapID)
        app.beforeGuardedSaveWriteForTesting = {
            precondition(identity(swap) == originalSwapID && identity(replacement) == replacedID)
            var vacant = stat()
            precondition(lstat(parked.path, &vacant) != 0 && errno == ENOENT)
            precondition(rename(swap.path, parked.path) == 0)
            precondition(rename(replacement.path, swap.path) == 0)
        }
        do { try app.saveCurrentMap(to: swap); fatalError("Swapped destination must conflict") }
        catch NativeMapFile.FileError.conflict { }
        app.beforeGuardedSaveWriteForTesting = nil
        let swappedBytes = try Data(contentsOf: swap)
        assert(identity(swap) == replacedID && swappedBytes == replacedBytes)
        assert(identity(parked) == originalSwapID && a.fileURL == aURL && a.dirty)

        let newDestination = directory.appendingPathComponent("new.mflw")
        let incoming = directory.appendingPathComponent("incoming.mflw")
        try NativeMapFile.write(.init(document: OwnMapDocument(roots: [bNode]), mindNodeArchive: nil), to: incoming)
        let incomingBytes = try Data(contentsOf: incoming)
        let incomingID = identity(incoming)
        app.beforeGuardedSaveWriteForTesting = {
            var absent = stat()
            precondition(lstat(newDestination.path, &absent) != 0 && errno == ENOENT)
            precondition(identity(incoming) == incomingID && rename(incoming.path, newDestination.path) == 0)
        }
        do { try app.saveCurrentMap(to: newDestination); fatalError("Expected absence becoming presence must conflict") }
        catch NativeMapFile.FileError.conflict { }
        app.beforeGuardedSaveWriteForTesting = nil
        let publishedBytes = try Data(contentsOf: newDestination)
        assert(identity(newDestination) == incomingID && publishedBytes == incomingBytes)
        assert(a.fileURL == aURL && a.dirty && a.canvas.model.roots == roots)
        assert(a.canvas.model.undo() && a.canvas.model.roots == [aNode], "Save As rejection preserves undo")
        a.canvas.addMainNode()
        try app.saveCurrentMap(to: aURL)
        assert(a.fileURL == aURL && !a.dirty)
        a.canvas.addMainNode()
        let genuinelyNew = directory.appendingPathComponent("genuinely-new.mflw")
        try app.saveCurrentMap(to: genuinelyNew)
        assert(a.fileURL == genuinelyNew && !a.dirty && identity(bURL) == originalID)
        assert(!first.window.isVisible && !second.window.isVisible)
        print("cross-session Save As destination collision rejected")
    }
}
