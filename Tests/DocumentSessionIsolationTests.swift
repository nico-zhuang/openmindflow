import AppKit
import Foundation
import Darwin

@main enum DocumentSessionIsolationTests {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/openmindflow-session-isolation-XXXXXX").utf8CString
        let path = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let result = mkdtemp(start) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return String(cString: result)
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        var owner = stat()
        guard lstat(folder.path, &owner) == 0, owner.st_uid == getuid(),
              owner.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              owner.st_mode & mode_t(0o777) == mode_t(0o700),
              folder.deletingLastPathComponent() == base,
              folder.resolvingSymlinksInPath().standardizedFileURL == folder else {
            fatalError("Fixture must be an owned 0700 mkdtemp directory")
        }
        let inode = owner.st_ino
        defer {
            var now = stat()
            if lstat(folder.path, &now) == 0, now.st_ino == inode, now.st_uid == getuid(),
               now.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
               folder.deletingLastPathComponent() == base,
               folder.resolvingSymlinksInPath().standardizedFileURL == folder {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        let defaults = UserDefaults(suiteName: "local.openmindflow.session-isolation.\(UUID())")!
        let app = AppDelegate(defaults: defaults)
        let rootA = MapNode(id: UUID(), title: "Alpha", children: [], folded: false)
        let rootB = MapNode(id: UUID(), title: "Beta", children: [], folded: false)
        let canvasA = MapCanvas(model: MapModel(roots: [rootA], selected: rootA.id))
        let canvasB = MapCanvas(model: MapModel(roots: [rootB], selected: rootB.id))
        let a = app.installAdditionalUnshownDocumentFixture(canvas: canvasA)
        let b = app.installAdditionalUnshownDocumentFixture(canvas: canvasB)
        assert(!a.window.isVisible && !a.window.isKeyWindow && !b.window.isVisible && !b.window.isKeyWindow)
        assert(a.session.canvas === canvasA && b.session.canvas === canvasB)
        assert(canvasA.model !== canvasB.model)
        assert(a.session.outline !== b.session.outline && a.session.inspector !== b.session.inspector)
        assert(a.session.splitController !== b.session.splitController)
        canvasA.model.rename("Alpha changed")
        canvasA.onChange?()
        assert(a.session.dirty && !b.session.dirty)
        let pathA = folder.appendingPathComponent("Alpha.mflw")
        let pathB = folder.appendingPathComponent("Beta.mflw")
        try a.session.saveCurrentMap(to: pathA)
        try b.session.saveCurrentMap(to: pathB)
        let savedA = try NativeMapFile.read(pathA)
        let savedB = try NativeMapFile.read(pathB)
        assert(savedA.document.roots.first?.title == "Alpha changed")
        assert(savedB.document.roots == [rootB])
        canvasA.undo()
        assert(canvasB.model.roots == [rootB])

        let source = folder.appendingPathComponent("Source.mindnode", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let raw: [String: Any] = ["nodeID": UUID().uuidString, "title": ["text": "<p>Imported B</p>"],
                                  "subnodes": [], "hasFoldedSubnodes": false]
        let plist: [String: Any] = ["version": 9, "canvas": ["mindMaps": [["mainNode": raw]]]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: source.appendingPathComponent("contents.xml"))
        let archive = try b.session.preflightMindNode(at: source)
        b.session.installDocument(LoadedDocument(document: OwnMapDocument(roots: archive.imported.roots),
                                                 archive: archive, nativeURL: nil, digest: nil, identity: nil))
        assert(b.session.mindNodeArchive != nil && a.session.mindNodeArchive == nil)
        a.session.installDocument(try a.session.preflightMap(at: pathA))
        assert(b.session.mindNodeArchive != nil && a.session.mindNodeArchive == nil)
        try Data("external replacement".utf8).write(to: pathA, options: .atomic)
        do {
            try a.session.saveCurrentMap(to: pathA)
            fatalError("A stale session must reject external replacement")
        } catch NativeMapFile.FileError.conflict { }
        try b.session.saveCurrentMap(to: pathB)
        let savedImportedB = try NativeMapFile.read(pathB)
        assert(savedImportedB.document.roots.first?.title == "Imported B")
        print("independent document sessions, MindNode provenance, undo, and stale-save guard passed")
    }
}
