import AppKit
import Foundation
import Darwin

@main enum NativeDocumentJourneyTests {
    static func main() throws {
        _ = NSApplication.shared // One synthetic, never ordered native window; no global AX/HID.
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/openmindflow-native-journey-XXXXXX").utf8CString
        let path = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let created = mkdtemp(start) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return String(cString: created)
        }
        let scratch = URL(fileURLWithPath: path, isDirectory: true)
        var inode = stat()
        guard lstat(scratch.path, &inode) == 0, inode.st_uid == getuid(),
              inode.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              inode.st_mode & mode_t(0o777) == mode_t(0o700),
              scratch.deletingLastPathComponent() == base,
              scratch.resolvingSymlinksInPath().standardizedFileURL == scratch else {
            fatalError("Not an exclusively owned synthetic fixture")
        }
        let fixtureInode = inode.st_ino
        defer {
            var current = stat()
            if lstat(scratch.path, &current) == 0, current.st_ino == fixtureInode,
               current.st_uid == getuid(), current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
               scratch.deletingLastPathComponent() == base,
               scratch.resolvingSymlinksInPath().standardizedFileURL == scratch {
                try? fm.removeItem(at: scratch)
            }
        }
        let source = scratch.appendingPathComponent("original.mindnode", isDirectory: true)
        try fm.createDirectory(at: source.appendingPathComponent("assets"), withIntermediateDirectories: true)
        let id = UUID()
        let raw: [String: Any] = ["nodeID": id.uuidString,
            "title": ["text": "<p>Original</p>"], "subnodes": [],
            "hasFoldedSubnodes": false, "opaqueNote": ["unknown": "keep"]]
        let plist: [String: Any] = ["version": 9, "canvas": ["mindMaps": [["mainNode": raw]]],
                                    "opaqueDocumentKey": "preserve unchanged"]
        let originalContents = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let sourceResource = Data([0, 4, 255, 33])
        try originalContents.write(to: source.appendingPathComponent("contents.xml"))
        try sourceResource.write(to: source.appendingPathComponent("assets/raw.bin"))
        let archive = try MindNodeArchive(importing: source)
        assert(archive.imported.roots.first?.title == "Original")
        let edited = MapNode(id: id, title: "Edited <&> 🌿", children: [], folded: true)
        let native = scratch.appendingPathComponent("Working.mflw")
        let envelope = try PropertyListEncoder().encode(archive)
        let document = OwnMapDocument(roots: [edited])
        try NativeMapFile.write(.init(document: document, mindNodeArchive: envelope), to: native)
        let rawNative = try Data(contentsOf: native)
        assert(rawNative.starts(with: Data("OMFLW001".utf8)) && !rawNative.starts(with: Data("{".utf8)),
               "The editable native document is binary and carries its own magic, never renamed JSON")
        let reopened = try NativeMapFile.read(native)
        assert(reopened.document.roots == [edited] && reopened.mindNodeArchive != nil)
        let reopenedArchive = try PropertyListDecoder().decode(MindNodeArchive.self, from: reopened.mindNodeArchive!)
        let rendered = MapCanvas(model: MapModel(roots: reopened.document.roots, selected: edited.id))
        let syntheticWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
        syntheticWindow.contentView = rendered
        assert(!syntheticWindow.isVisible && !syntheticWindow.isKeyWindow)
        assert(rendered.frameForAccessibility(edited.id) != nil)
        let exported = scratch.appendingPathComponent("Exported.mindnode", isDirectory: true)
        try reopenedArchive.export(document: reopened.document, to: exported)
        let reimported = try MindNodeImporter.load(exported)
        let exportedResource = try Data(contentsOf: exported.appendingPathComponent("assets/raw.bin"))
        let originalPlistAfter = try Data(contentsOf: source.appendingPathComponent("contents.xml"))
        let originalResourceAfter = try Data(contentsOf: source.appendingPathComponent("assets/raw.bin"))
        assert(reimported == [edited] && exportedResource == sourceResource)
        assert(originalPlistAfter == originalContents && originalResourceAfter == sourceResource)
        let exportedRoot = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: exported.appendingPathComponent("contents.xml")), format: nil) as! [String: Any]
        assert(exportedRoot["opaqueDocumentKey"] as? String == "preserve unchanged")
        syntheticWindow.orderOut(nil)

        // Exercise the real document actions without showing or activating a user window.
        let defaults = UserDefaults(suiteName: "local.openmindflow.native-journey.\(UUID())")!
        L10n.setLanguage("en", defaults: defaults)
        let seed = MapNode(id: UUID(), title: "Seed", children: [], folded: false)
        let workbenchCanvas = MapCanvas(model: MapModel(roots: [seed], selected: seed.id))
        let app = AppDelegate(defaults: defaults)
        let workbenchWindow = app.installUnshownDocumentFixture(canvas: workbenchCanvas)
        assert(!workbenchWindow.isVisible && !workbenchWindow.isKeyWindow)
        try app.loadMindNode(at: source)
        assert(workbenchCanvas.model.roots.first?.title == "Original")
        workbenchCanvas.model.rename("Edited from the menu 🌿")
        let working = scratch.appendingPathComponent("Saved-by-App.mflw")
        try app.saveCurrentMap(to: working)
        assert(!workbenchWindow.title.contains(" •"))
        let saved = try NativeMapFile.read(working)
        assert(saved.document.roots.first?.title == "Edited from the menu 🌿" && saved.mindNodeArchive != nil)
        try app.loadMap(at: working)
        assert(workbenchCanvas.model.roots.first?.title == "Edited from the menu 🌿")
        let fromApp = scratch.appendingPathComponent("From-App.mindnode", isDirectory: true)
        try app.exportCurrentMindNode(to: fromApp)
        let fromAppRoots = try MindNodeImporter.load(fromApp)
        assert(fromAppRoots.first?.title == "Edited from the menu 🌿")
        let fromAppResource = try Data(contentsOf: fromApp.appendingPathComponent("assets/raw.bin"))
        assert(fromAppResource == sourceResource)
        workbenchCanvas.model.addMainNode()
        let unsupported = scratch.appendingPathComponent("Unsupported-Edit.mindnode")
        do {
            try app.exportCurrentMindNode(to: unsupported)
            fatalError("Adding a node must not flatten unknown MindNode package metadata")
        } catch { assert(!fm.fileExists(atPath: unsupported.path)) }
        try app.saveCurrentMap(to: working) // Unsupported export edits remain safe in native format.
        let nativeEdited = try NativeMapFile.read(working)
        assert(nativeEdited.document.roots.count == 2)
        let savedBeforeExternal = try Data(contentsOf: working)
        let external = Data("external update".utf8)
        try external.write(to: working, options: .atomic)
        workbenchCanvas.model.rename("Still unsaved")
        workbenchCanvas.onChange?() // Direct model mutation needs the normal canvas change callback.
        do {
            try app.saveCurrentMap(to: working)
            fatalError("A stale native save must not overwrite an external revision")
        } catch NativeMapFile.FileError.conflict { }
        let externalAfter = try Data(contentsOf: working)
        assert(externalAfter == external && workbenchWindow.title.contains(" •"))
        let hardlinkAlias = scratch.appendingPathComponent("Another-Name.mflw")
        try fm.linkItem(at: working, to: hardlinkAlias)
        do {
            try app.saveCurrentMap(to: hardlinkAlias)
            throw NSError(domain: "NativeJourney", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Save As bypassed the stale digest through a hardlink alias"])
        } catch NativeMapFile.FileError.conflict { }
        let aliasedAfter = try Data(contentsOf: hardlinkAlias)
        let primaryAfterAlias = try Data(contentsOf: working)
        assert(aliasedAfter == external && primaryAfterAlias == external)
        let caseAlias = scratch.appendingPathComponent("saved-by-app.mflw")
        var caseFile = stat()
        if lstat(caseAlias.path, &caseFile) == 0 {
            do {
                try app.saveCurrentMap(to: caseAlias)
                throw NSError(domain: "NativeJourney", code: 12,
                              userInfo: [NSLocalizedDescriptionKey: "Save As bypassed the stale digest via APFS case alias"])
            } catch NativeMapFile.FileError.conflict { }
            let primaryAfterCaseAlias = try Data(contentsOf: working)
            assert(primaryAfterCaseAlias == external)
        }
        let relocated = scratch.appendingPathComponent("Finder-Renamed.mflw")
        var beforeMove = stat()
        guard working.deletingLastPathComponent() == scratch,
              relocated.deletingLastPathComponent() == scratch,
              lstat(working.path, &beforeMove) == 0, beforeMove.st_uid == getuid(),
              beforeMove.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              !fm.fileExists(atPath: relocated.path) else {
            fatalError("Finder-rename test may move only its owned synthetic map")
        }
        try fm.moveItem(at: working, to: relocated)
        do {
            try app.saveCurrentMap(to: relocated)
            throw NSError(domain: "NativeJourney", code: 13,
                          userInfo: [NSLocalizedDescriptionKey: "Save As overwrote a renamed and externally edited map"])
        } catch NativeMapFile.FileError.conflict { }
        let relocatedAfter = try Data(contentsOf: relocated)
        assert(relocatedAfter == external && workbenchWindow.title.contains(" •"))
        try savedBeforeExternal.write(to: working, options: .atomic) // A copy, not the originally opened inode.
        do {
            try app.saveCurrentMap(to: relocated)
            throw NSError(domain: "NativeJourney", code: 14,
                          userInfo: [NSLocalizedDescriptionKey: "Save As trusted a copy restored at the old source path"])
        } catch NativeMapFile.FileError.conflict { }
        let relocatedAfterCopyBack = try Data(contentsOf: relocated)
        assert(relocatedAfterCopyBack == external)
        let uncommittedRoots = workbenchCanvas.model.roots
        let invalidNative = scratch.appendingPathComponent("Invalid.mflw")
        try Data("not a native map".utf8).write(to: invalidNative)
        do { try app.loadMap(at: invalidNative); fatalError("Invalid files must fail before a discard prompt") }
        catch { assert(workbenchCanvas.model.roots == uncommittedRoots && workbenchWindow.title.contains(" •")) }
        let invalidMindNode = scratch.appendingPathComponent("Invalid.mindnode", isDirectory: true)
        try fm.createDirectory(at: invalidMindNode, withIntermediateDirectories: false)
        try Data("not a binary plist".utf8).write(to: invalidMindNode.appendingPathComponent("contents.xml"))
        do { try app.loadMindNode(at: invalidMindNode); fatalError("Invalid imports must not replace unsaved maps") }
        catch { assert(workbenchCanvas.model.roots == uncommittedRoots && workbenchWindow.title.contains(" •")) }
        let freshSaveAs = scratch.appendingPathComponent("Safe-New-Name.mflw")
        try app.saveCurrentMap(to: freshSaveAs)
        let untouchedMoved = try Data(contentsOf: relocated)
        let freshMap = try NativeMapFile.read(freshSaveAs)
        assert(untouchedMoved == external && freshMap.document.roots == uncommittedRoots)

        let legacy = scratch.appendingPathComponent("Legacy.mindmap.json")
        try writeOwnDocument(OwnMapDocument(roots: [seed]), to: legacy)
        let originalLegacy = try Data(contentsOf: legacy)
        let migrating = AppDelegate(defaults: defaults)
        let legacyCanvas = MapCanvas(model: MapModel(roots: [seed], selected: seed.id))
        let legacyWindow = migrating.installUnshownDocumentFixture(canvas: legacyCanvas)
        try migrating.loadMap(at: legacy)
        let migrated = scratch.appendingPathComponent("Migrated.mflw")
        try migrating.saveCurrentMap(to: migrated)
        let legacyAfter = try Data(contentsOf: legacy)
        let migratedMap = try NativeMapFile.read(migrated)
        assert(legacyAfter == originalLegacy && migratedMap.document.roots == [seed])
        let otherRoot = MapNode(id: UUID(), title: "Other document", children: [], folded: false)
        let replaceable = scratch.appendingPathComponent("Confirmed-Replacement.mflw")
        try NativeMapFile.write(NativeMapFile.Payload(document: OwnMapDocument(roots: [otherRoot]),
                                                  mindNodeArchive: nil), to: replaceable)
        let originalMigrationBytes = try Data(contentsOf: migrated)
        try migrating.saveCurrentMap(to: replaceable) // Models Save As after an explicit panel Replace confirmation.
        let replacement = try NativeMapFile.read(replaceable)
        let migrationBytesAfter = try Data(contentsOf: migrated)
        assert(replacement.document.roots == [seed] && migrationBytesAfter == originalMigrationBytes)
        assert(!legacyWindow.isVisible)
        // Finder may deliver a document before AppKit has finished constructing its window.
        let finder = AppDelegate(defaults: defaults)
        finder.application(NSApplication.shared, open: [migrated])
        let placeholder = MapNode(id: UUID(), title: "Not the Finder map", children: [], folded: false)
        let finderCanvas = MapCanvas(model: MapModel(roots: [placeholder], selected: placeholder.id))
        let finderWindow = finder.installUnshownDocumentFixture(canvas: finderCanvas)
        assert(finderCanvas.model.roots == [seed] && !finderWindow.isVisible)
        finderWindow.orderOut(nil)
        workbenchWindow.orderOut(nil)
        legacyWindow.orderOut(nil)
        print("native App actions, mflw/legacy migration, stale-save protection, and preserved MindNode export passed in unshown windows")
    }
}
