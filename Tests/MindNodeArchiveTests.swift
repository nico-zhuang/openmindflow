import Foundation
import Darwin
import CryptoKit

@main enum MindNodeArchiveTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/mindnode-archive-XXXXXX").utf8CString
        let path = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let made = mkdtemp(start) else { throw POSIXError(.EIO) }
            return String(cString: made)
        }
        let scratch = URL(fileURLWithPath: path, isDirectory: true)
        var fixture = stat()
        guard lstat(scratch.path, &fixture) == 0, fixture.st_uid == getuid(),
              fixture.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              fixture.st_mode & mode_t(0o777) == mode_t(0o700),
              scratch.deletingLastPathComponent() == base,
              scratch.resolvingSymlinksInPath().standardizedFileURL == scratch else {
            fatalError("Archive fixture must be a private owned directory")
        }
        let fixtureInode = fixture.st_ino
        defer {
            var current = stat()
            if lstat(scratch.path, &current) == 0, current.st_ino == fixtureInode,
               current.st_uid == getuid(), current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
               scratch.deletingLastPathComponent() == base,
               scratch.resolvingSymlinksInPath().standardizedFileURL == scratch {
                try? fm.removeItem(at: scratch)
            }
        }
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { throw NSError(domain: "ArchiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func rejects(_ destination: URL, _ body: () throws -> Void) throws {
            do { try body(); throw NSError(domain: "ArchiveTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected success: \(destination.path)"]) }
            catch let error as NSError where error.domain == "ArchiveTests" && error.code == 2 { throw error }
            catch { try check(lstatExists(destination.path) == false, "failed export published destination") }
        }
        let rootID = UUID(), firstID = UUID(), secondID = UUID()
        let first: [String: Any] = ["nodeID": firstID.uuidString, "title": ["text": "<p>First</p>"], "subnodes": [], "hasFoldedSubnodes": false, "attachment": ["resource": "assets/media.bin"]]
        let second: [String: Any] = ["nodeID": secondID.uuidString, "title": ["text": "<p>Rich <b>title</b></p>"], "subnodes": [], "hasFoldedSubnodes": false, "notes": ["text": "unparsed"]]
        let root: [String: Any] = ["nodeID": rootID.uuidString, "title": ["text": "<p>Root</p>", "unknown": "stay"], "subnodes": [first, second], "hasFoldedSubnodes": false, "unknown": Data([1,2,3])]
        let plist: [String: Any] = ["version": 9, "canvas": ["mindMaps": [["mainNode": root]], "crossConnections": [["opaque": "link"]]], "unknownRoot": ["a": 19]]
        let contents = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let source = scratch.appendingPathComponent("original.mindnode", isDirectory: true)
        try fm.createDirectory(at: source.appendingPathComponent("assets/deep"), withIntermediateDirectories: true)
        try fm.createDirectory(at: source.appendingPathComponent("style.mindnodestyle"), withIntermediateDirectories: true)
        let resource = Data([0, 255, 3, 0, 42]), theme = Data([7, 8, 9])
        try contents.write(to: source.appendingPathComponent("contents.xml"))
        try resource.write(to: source.appendingPathComponent("assets/deep/media.bin"))
        try theme.write(to: source.appendingPathComponent("style.mindnodestyle/opaque"))
        let originalHash = SHA256.hash(data: contents)
        let archive = try MindNodeArchive(importing: source)
        try check(archive.imported.hasUnimportedConnections && archive.imported.hasUnimportedAttachments && archive.imported.hasUnimportedRichTitles, "lost import flags")
        let rejectedRelationship = scratch.appendingPathComponent("relationship-rejected.mindnode")
        let relationship = MapRelationship(from: rootID, to: firstID)
        try rejects(rejectedRelationship) {
            try archive.export(document: OwnMapDocument(roots: archive.imported.roots,
                relationships: [relationship]), to: rejectedRelationship)
        }
        let rejectedTheme = scratch.appendingPathComponent("theme-rejected.mindnode")
        try rejects(rejectedTheme) {
            try archive.export(document: OwnMapDocument(roots: archive.imported.roots, theme: "classic"), to: rejectedTheme)
        }
        let rejectedCanvas = scratch.appendingPathComponent("canvas-rejected.mindnode")
        try rejects(rejectedCanvas) {
            try archive.export(document: OwnMapDocument(roots: archive.imported.roots, canvasColor: "#112233FF"), to: rejectedCanvas)
        }
        let encoded = try PropertyListEncoder().encode(archive)
        let restored = try PropertyListDecoder().decode(MindNodeArchive.self, from: encoded)
        let unedited = scratch.appendingPathComponent("unedited.mindnode")
        try restored.export(document: OwnMapDocument(roots: restored.imported.roots), to: unedited)
        try check(try Data(contentsOf: unedited.appendingPathComponent("contents.xml")) == contents, "unedited plist not byte-exact")
        var edited = restored.imported.roots
        edited[0].title = "Edited <&> 🧭"
        edited[0].folded = true
        edited[0].children.swapAt(0, 1)
        let exported = scratch.appendingPathComponent("export.mindnode")
        try restored.export(document: OwnMapDocument(roots: edited), to: exported)
        try check(try MindNodeImporter.load(exported) == edited, "round trip edited tree")
        try check(try Data(contentsOf: exported.appendingPathComponent("assets/deep/media.bin")) == resource, "resource changed")
        try check(try Data(contentsOf: exported.appendingPathComponent("style.mindnodestyle/opaque")) == theme, "theme changed")
        try check(SHA256.hash(data: try Data(contentsOf: source.appendingPathComponent("contents.xml"))) == originalHash, "source changed")
        let updated = try PropertyListSerialization.propertyList(from: Data(contentsOf: exported.appendingPathComponent("contents.xml")), format: nil) as! [String: Any]
        try check((updated["unknownRoot"] as? [String: Int]) == ["a": 19], "unknown plist key changed")
        let updatedRoot = (((updated["canvas"] as! [String: Any])["mindMaps"] as! [[String: Any]])[0]["mainNode"] as! [String: Any])
        try check((updatedRoot["unknown"] as? Data) == Data([1,2,3]), "unknown node field changed")
        let outputChildren = updatedRoot["subnodes"] as! [[String: Any]]
        try check((outputChildren[0]["notes"] as? [String: String]) == ["text": "unparsed"], "reordered metadata lost")
        let regular = scratch.appendingPathComponent("regular.mindnode")
        try contents.write(to: regular)
        let regularArchive = try MindNodeArchive(importing: regular)
        let portable = try PropertyListDecoder().decode(MindNodeArchive.self, from: PropertyListEncoder().encode(regularArchive))
        try fm.removeItem(at: regular)
        let regularCopy = scratch.appendingPathComponent("regular-copy.mindnode")
        try portable.export(document: OwnMapDocument(roots: edited), to: regularCopy)
        try check(try MindNodeImporter.load(regularCopy) == edited, "regular-file export failed")
        try check(lstatType(regularCopy.path) == mode_t(S_IFREG), "regular source became directory")
        let nestedSource = scratch.appendingPathComponent("nested.mindnode", isDirectory: true)
        let nestedAssets = nestedSource.appendingPathComponent("assets/deep", isDirectory: true)
        try fm.createDirectory(at: nestedAssets, withIntermediateDirectories: true)
        try contents.write(to: nestedSource.appendingPathComponent("contents.xml"))
        for index in 0..<120 {
            try Data([UInt8(index)]).write(to: nestedAssets.appendingPathComponent("part-\(index).bin"))
        }
        // Capture before changing the process-wide limit: only export runs with fewer FDs.
        let nestedArchive = try MindNodeArchive(importing: nestedSource)
        let nestedOutput = scratch.appendingPathComponent("nested-copy.mindnode")
        try { () throws in
            var originalLimit = rlimit()
            try check(getrlimit(RLIMIT_NOFILE, &originalLimit) == 0 && originalLimit.rlim_cur >= 128,
                      "could not read a sufficient original FD limit")
            var constrained = originalLimit
            constrained.rlim_cur = 128
            try check(setrlimit(RLIMIT_NOFILE, &constrained) == 0, "could not constrain FD limit")
            defer { _ = setrlimit(RLIMIT_NOFILE, &originalLimit) }
            do {
                try nestedArchive.export(document: OwnMapDocument(roots: nestedArchive.imported.roots), to: nestedOutput)
            } catch {
                throw NSError(domain: "ArchiveTests", code: 10,
                              userInfo: [NSLocalizedDescriptionKey: "nested low-FD export failed: \(error)"])
            }
        }()
        try check(try Data(contentsOf: nestedOutput.appendingPathComponent("assets/deep/part-119.bin")) == Data([119]),
                  "nested low-FD export lost a resource")
        let tooDeep = scratch.appendingPathComponent("too-deep.mindnode", isDirectory: true)
        var deepPath = tooDeep
        for index in 0..<33 { deepPath.appendPathComponent("d\(index)", isDirectory: true) }
        try fm.createDirectory(at: deepPath, withIntermediateDirectories: true)
        try contents.write(to: tooDeep.appendingPathComponent("contents.xml"))
        try Data([1]).write(to: deepPath.appendingPathComponent("asset"))
        do { _ = try MindNodeArchive(importing: tooDeep); throw NSError(domain: "ArchiveTests", code: 11) }
        catch let error as NSError where error.domain == "ArchiveTests" && error.code == 11 { throw error }
        catch { }
        var unsupported = edited
        unsupported[0].children[0].title = "flattened rich"
        let badRich = scratch.appendingPathComponent("bad-rich.mindnode")
        try rejects(badRich) { try restored.export(document: OwnMapDocument(roots: unsupported), to: badRich) }
        unsupported = edited; unsupported[0].children[1].children.append(MapNode(id: UUID(), title: "new", children: [], folded: false))
        let badStructure = scratch.appendingPathComponent("bad-structure.mindnode")
        try rejects(badStructure) { try restored.export(document: OwnMapDocument(roots: unsupported), to: badStructure) }
        unsupported = edited; unsupported[0].width = 201
        let badWidth = scratch.appendingPathComponent("bad-width.mindnode")
        try rejects(badWidth) { try restored.export(document: OwnMapDocument(roots: unsupported), to: badWidth) }
        unsupported = edited; unsupported[0].note = "new note"
        let badNote = scratch.appendingPathComponent("bad-note.mindnode")
        try rejects(badNote) { try restored.export(document: OwnMapDocument(roots: unsupported), to: badNote) }
        unsupported = edited; unsupported[0].fontFamily = "Helvetica"
        let badStyle = scratch.appendingPathComponent("bad-style.mindnode")
        try rejects(badStyle) { try restored.export(document: OwnMapDocument(roots: unsupported), to: badStyle) }
        let occupied = scratch.appendingPathComponent("occupied.mindnode")
        try Data([42]).write(to: occupied)
        do { try restored.export(document: OwnMapDocument(roots: edited), to: occupied); throw NSError(domain: "ArchiveTests", code: 3) }
        catch let error as NSError where error.domain == "ArchiveTests" && error.code == 3 { throw error }
        catch { try check(try Data(contentsOf: occupied) == Data([42]), "occupied target overwritten") }
        let linkedDestination = scratch.appendingPathComponent("occupied-link.mindnode")
        try fm.createSymbolicLink(at: linkedDestination, withDestinationURL: source)
        do { try restored.export(document: OwnMapDocument(roots: edited), to: linkedDestination); throw NSError(domain: "ArchiveTests", code: 9) }
        catch let error as NSError where error.domain == "ArchiveTests" && error.code == 9 { throw error }
        catch { try check(lstatType(linkedDestination.path) == mode_t(S_IFLNK), "destination symlink replaced") }
        let unsafeParent = scratch.appendingPathComponent("world-writable", isDirectory: true)
        try fm.createDirectory(at: unsafeParent, withIntermediateDirectories: false)
        try fm.setAttributes([.posixPermissions: 0o777], ofItemAtPath: unsafeParent.path)
        let unsafeOutput = unsafeParent.appendingPathComponent("unsafe.mindnode")
        try rejects(unsafeOutput) { try restored.export(document: OwnMapDocument(roots: edited), to: unsafeOutput) }
        let symlinked = scratch.appendingPathComponent("linked.mindnode")
        try fm.createSymbolicLink(at: symlinked, withDestinationURL: source)
        do { _ = try MindNodeArchive(importing: symlinked); throw NSError(domain: "ArchiveTests", code: 4) }
        catch let error as NSError where error.domain == "ArchiveTests" && error.code == 4 { throw error }
        catch { }
        let linkInside = source.appendingPathComponent("assets/escape")
        try fm.createSymbolicLink(at: linkInside, withDestinationURL: scratch)
        do { _ = try MindNodeArchive(importing: source); throw NSError(domain: "ArchiveTests", code: 5) }
        catch let error as NSError where error.domain == "ArchiveTests" && error.code == 5 { throw error }
        catch { }
        try fm.removeItem(at: linkInside)
        let oversized = scratch.appendingPathComponent("huge.mindnode")
        let fd = open(oversized.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        try check(fd >= 0 && ftruncate(fd, 64 * 1024 * 1024 + 1) == 0, "could not create sparse large file")
        _ = close(fd)
        do { _ = try MindNodeArchive(importing: oversized); throw NSError(domain: "ArchiveTests", code: 6) }
        catch let error as NSError where error.domain == "ArchiveTests" && error.code == 6 { throw error }
        catch { }
        let countSource = scratch.appendingPathComponent("count.mindnode", isDirectory: true)
        try fm.createDirectory(at: countSource, withIntermediateDirectories: false)
        try contents.write(to: countSource.appendingPathComponent("contents.xml"))
        for index in 0..<1000 { try Data().write(to: countSource.appendingPathComponent("item-\(index)")) }
        do { _ = try MindNodeArchive(importing: countSource); throw NSError(domain: "ArchiveTests", code: 7) }
        catch let error as NSError where error.domain == "ArchiveTests" && error.code == 7 { throw error }
        catch { }
        let encodedPlist = try PropertyListSerialization.propertyList(from: encoded, format: nil) as! [String: Any]
        func rejectsDecoded(_ mutate: (inout [String: Any]) -> Void) throws {
            var candidate = encodedPlist
            mutate(&candidate)
            let bytes = try PropertyListSerialization.data(fromPropertyList: candidate, format: .binary, options: 0)
            do { _ = try PropertyListDecoder().decode(MindNodeArchive.self, from: bytes)
                throw NSError(domain: "ArchiveTests", code: 8) }
            catch let error as NSError where error.domain == "ArchiveTests" && error.code == 8 { throw error }
            catch { }
        }
        try rejectsDecoded { $0["version"] = 77 }
        try rejectsDecoded { object in
            var items = object["entries"] as! [[String: Any]]
            items[0]["path"] = "../escape"
            object["entries"] = items
        }
        try rejectsDecoded { object in
            var items = object["entries"] as! [[String: Any]]
            items[0]["path"] = "assets/../../escape"
            object["entries"] = items
        }
        try rejectsDecoded { object in
            var items = object["entries"] as! [[String: Any]]
            var path = ""
            for index in 0..<33 {
                path += path.isEmpty ? "d\(index)" : "/d\(index)"
                items.append(["path": path])
            }
            object["entries"] = items
        }
        try rejectsDecoded { object in
            var items = object["entries"] as! [[String: Any]]
            items.append(items[0]); object["entries"] = items
        }
        try rejectsDecoded { object in
            var items = object["entries"] as! [[String: Any]]
            let index = items.firstIndex { ($0["path"] as? String) == "contents.xml" }!
            items[index]["data"] = Data([0x01, 0x02])
            object["entries"] = items
        }
        // Retargeting a symlinked ancestor must not mix A's captured bytes with B's metadata.
        let aliasA = scratch.appendingPathComponent("alias-a"), aliasB = scratch.appendingPathComponent("alias-b")
        try fm.createDirectory(at: aliasA, withIntermediateDirectories: false)
        try fm.createDirectory(at: aliasB, withIntermediateDirectories: false)
        let alternateID = UUID()
        for (parent, id) in [(aliasA, rootID), (aliasB, alternateID)] {
            let package = parent.appendingPathComponent("alias-source.mindnode")
            try fm.createDirectory(at: package, withIntermediateDirectories: false)
            var value = plist, canvas = value["canvas"] as! [String: Any]
            var maps = canvas["mindMaps"] as! [[String: Any]]
            var node = maps[0]["mainNode"] as! [String: Any]
            node["nodeID"] = id.uuidString; maps[0]["mainNode"] = node
            canvas["mindMaps"] = maps; value["canvas"] = canvas
            try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
                .write(to: package.appendingPathComponent("contents.xml"))
        }
        let alias = scratch.appendingPathComponent("moving-parent"), next = scratch.appendingPathComponent("next-parent")
        try fm.createSymbolicLink(at: alias, withDestinationURL: aliasA)
        let finished = DispatchSemaphore(value: 0), stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            while finished.wait(timeout: .now()) == .timedOut {
                try? fm.createSymbolicLink(at: next, withDestinationURL: aliasB)
                _ = rename(next.path, alias.path)
                try? fm.createSymbolicLink(at: next, withDestinationURL: aliasA)
                _ = rename(next.path, alias.path)
            }
            stopped.signal()
        }
        defer { finished.signal(); stopped.wait() }
        var observed = 0
        for _ in 0..<160 {
            guard let captured = try? MindNodeArchive(importing: alias.appendingPathComponent("alias-source.mindnode")) else { continue }
            let bytes = try PropertyListEncoder().encode(captured)
            let record = try PropertyListSerialization.propertyList(from: bytes, format: nil) as! [String: Any]
            let entries = record["entries"] as! [[String: Any]]
            let contents = entries.first { ($0["path"] as? String) == "contents.xml" }!["data"] as! Data
            let value = try PropertyListSerialization.propertyList(from: contents, format: nil) as! [String: Any]
            let canvas = value["canvas"] as! [String: Any]
            let main = (canvas["mindMaps"] as! [[String: Any]])[0]["mainNode"] as! [String: Any]
            try check(captured.imported.roots[0].id.uuidString == main["nodeID"] as? String,
                      "detailed import disagrees with captured source")
            observed += 1
        }
        try check(observed > 0, "alias race produced no usable snapshots")
        // Cleanup must not recursively delete a same-UID replacement of its stage pathname.
        let many = scratch.appendingPathComponent("many.mindnode")
        try fm.createDirectory(at: many, withIntermediateDirectories: false)
        try contents.write(to: many.appendingPathComponent("contents.xml"))
        for index in 0..<600 { try Data([UInt8(index % 256)]).write(to: many.appendingPathComponent("part-\(index)")) }
        let busy = try MindNodeArchive(importing: many)
        let rescued = scratch.appendingPathComponent("rescued-stage")
        let trapped = DispatchSemaphore(value: 0), ready = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            ready.signal()
            while trapped.wait(timeout: .now()) == .timedOut {
                guard let names = try? fm.contentsOfDirectory(atPath: scratch.path) else { continue }
                for name in names where name.hasPrefix(".mindnode-archive-") {
                    let path = scratch.appendingPathComponent(name)
                    guard rename(path.path, rescued.path) == 0 else { continue }
                    try? fm.createDirectory(at: path, withIntermediateDirectories: false)
                    try? Data("do not delete".utf8).write(to: path.appendingPathComponent("sentinel"))
                    trapped.signal()
                    return
                }
            }
        }
        ready.wait()
        let target = scratch.appendingPathComponent("interrupted.mindnode")
        _ = try? busy.export(document: OwnMapDocument(roots: busy.imported.roots), to: target)
        try check(trapped.wait(timeout: .now()) == .success, "stage swap was not observed")
        let stageNames = try fm.contentsOfDirectory(atPath: scratch.path).filter { $0.hasPrefix(".mindnode-archive-") }
        try check(stageNames.contains { (try? Data(contentsOf: scratch.appendingPathComponent($0).appendingPathComponent("sentinel"))) == Data("do not delete".utf8) },
                  "cleanup deleted a replaced stage directory")
        let broken = scratch.appendingPathComponent("broken.mindnode")
        try rejects(broken) { try restored.export(document: OwnMapDocument(roots: [MapNode(id: UUID(), title: "replaced", children: [], folded: false)]), to: broken) }
        print("MindNode archive portable source, edit preservation, regular file, and refusal tests passed")
    }
    static func lstatExists(_ path: String) -> Bool { var s = stat(); return lstat(path, &s) == 0 }
    static func lstatType(_ path: String) -> mode_t { var s = stat(); return lstat(path, &s) == 0 ? s.st_mode & mode_t(S_IFMT) : 0 }
}
