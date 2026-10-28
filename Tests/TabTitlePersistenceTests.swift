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
        for invalid in ["", " \n ", "a\u{0}b", "bad\u{7F}name", "a\nb",
                        "a\u{2028}b", "a\u{2029}b", "\u{2028}start", "end\u{2029}",
                        String(repeating: "a", count: 129), String(repeating: "界", count: 86)] {
            assert(!first.renameTab(to: invalid), "Must reject unsafe title: \(invalid.debugDescription)")
            assert(first.tabTitleOverride == "Café" && first.dirty)
        }
        assert(second.renameTab(to: "Second"))
        assert(secondOwner.window.title.contains("Second") && firstOwner.window.title.contains("Café"))
        let invalidDirectWrite = folder.appendingPathComponent("invalid-direct-write.mflw")
        for separator in ["\u{2028}", "\u{2029}"] {
            let badTitle = "before\(separator)after"
            assert(CharacterSet.newlines.contains(separator.unicodeScalars.first!))
            assert(!CharacterSet.controlCharacters.contains(separator.unicodeScalars.first!))
            do {
                try NativeMapFile.write(.init(document: document, mindNodeArchive: nil, tabTitle: badTitle),
                                        to: invalidDirectWrite)
                assertionFailure("Native write accepted a Unicode line/paragraph separator")
            } catch NativeMapFile.FileError.corrupt { }
            assert(!FileManager.default.fileExists(atPath: invalidDirectWrite.path),
                   "An invalid title must not publish a native file")
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let body = try encoder.encode(NativeMapFile.Payload(document: document, mindNodeArchive: nil,
                                                                tabTitle: badTitle))
            assert(body.starts(with: Data("bplist00".utf8)))
            var crafted = Data("OMFLW001".utf8)
            var length = UInt64(body.count).bigEndian
            withUnsafeBytes(of: &length) { crafted.append(contentsOf: $0) }
            crafted.append(contentsOf: SHA256.hash(data: body))
            crafted.append(body)
            let forged = folder.appendingPathComponent("crafted-\(separator == "\u{2028}" ? "line" : "paragraph").mflw")
            try crafted.write(to: forged)
            do {
                _ = try NativeMapFile.read(forged)
                assertionFailure("A correctly framed and hashed native file accepted unsafe title metadata")
            } catch NativeMapFile.FileError.corrupt { }
        }
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
        assert(first.renameTab(to: "Title-only unsaved conflict") && first.dirty)
        assert(first.canvas.model.roots == document.roots, "Only title metadata changed")
        try NativeMapFile.write(.init(document: document, mindNodeArchive: nil, tabTitle: "External writer"),
                                to: savedAs)
        let externallyWritten = try Data(contentsOf: savedAs)
        do {
            try first.saveCurrentMap(to: savedAs)
            assertionFailure("An external native-file replacement must trigger a save conflict")
        } catch NativeMapFile.FileError.conflict { }
        assert(first.dirty && first.tabTitleOverride == "Title-only unsaved conflict",
               "A title-only save conflict must leave the unsaved rename dirty")
        let diskAfterConflict = try Data(contentsOf: savedAs)
        assert(first.fileURL == savedAs && diskAfterConflict == externallyWritten)
        let reopened = DocumentSession(canvas: MapCanvas(model: MapModel(roots: [root], selected: root.id)), defaults: defaults)
        reopened.installDocument(try reopened.preflightMap(at: savedAs))
        assert(reopened.tabTitleOverride == "External writer" && !reopened.dirty)
        assert(reopened.displayTabTitle(defaults: defaults) == "External writer")
        assert(reopened.canvas.model.roots == document.roots && reopened.mindNodeArchive == nil)
        let legacy = folder.appendingPathComponent("legacy.mindmap.json")
        try writeOwnDocument(document, to: legacy)
        reopened.installDocument(try reopened.preflightMap(at: legacy))
        assert(reopened.tabTitleOverride == nil && reopened.displayTabTitle(defaults: defaults) == "Untitled")
        let unsaved = DocumentSession(canvas: MapCanvas(model: MapModel(roots: [root], selected: root.id)),
                                      defaults: defaults)
        assert(unsaved.fileURL == nil && unsaved.renameTab(to: "Brand New Tab") && unsaved.dirty)
        let privateSave = folder.appendingPathComponent("brand-new-private.mflw")
        try unsaved.saveCurrentMap(to: privateSave)
        assert(unsaved.fileURL == privateSave && !unsaved.dirty)
        let newlyReopened = DocumentSession(canvas: MapCanvas(model: MapModel(roots: [], selected: UUID())),
                                            defaults: defaults)
        newlyReopened.installDocument(try newlyReopened.preflightMap(at: privateSave))
        assert(newlyReopened.tabTitleOverride == "Brand New Tab" && !newlyReopened.dirty)
        assert(newlyReopened.canvas.model.roots == document.roots && newlyReopened.mindNodeArchive == nil)
        let syntheticMindNode = folder.appendingPathComponent("synthetic-import.mindnode", isDirectory: true)
        try MindNodeWriter.write(document.roots, to: syntheticMindNode, relationships: [])
        let importedArchive = try newlyReopened.preflightMindNode(at: syntheticMindNode)
        newlyReopened.installDocument(LoadedDocument(document: OwnMapDocument(roots: importedArchive.imported.roots),
                                                     archive: importedArchive, nativeURL: nil,
                                                     digest: nil, identity: nil))
        assert(newlyReopened.tabTitleOverride == nil && newlyReopened.fileURL == nil && !newlyReopened.dirty,
               "A synthetic MindNode import must not retain prior tab title metadata")
        print("tab title validation, malformed metadata refusal, conflict, fresh save/reopen, and import passed")
    }
}
