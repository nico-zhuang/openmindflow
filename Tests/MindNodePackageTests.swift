import Foundation

@main
enum MindNodePackageTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let scratch = base.appendingPathComponent("mindmap-copy-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: false)
        let marker = scratch.appendingPathComponent(".owner")
        let owner = UUID().uuidString
        try owner.write(to: marker, atomically: true, encoding: .utf8)
        defer {
            if scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
               scratch.deletingLastPathComponent() == base,
               (try? String(contentsOf: marker, encoding: .utf8)) == owner {
                try? fm.removeItem(at: scratch)
            }
        }
        let source = scratch.appendingPathComponent("source.mindnode", isDirectory: true)
        let output = scratch.appendingPathComponent("copy.mindnode", isDirectory: true)
        try fm.createDirectory(at: source.appendingPathComponent("assets"), withIntermediateDirectories: true)
        let rootID = UUID()
        let root: [String: Any] = ["nodeID": rootID.uuidString,
                                   "title": ["text": "<p>合成节点</p>"],
                                   "subnodes": [], "hasFoldedSubnodes": false,
                                   "unknownNodeField": ["color": "preserve"]]
        let plist: [String: Any] = ["version": 9,
                                    "canvas": ["mindMaps": [["mainNode": root]]],
                                    "unknownRootField": [1, 2, 3]]
        let contents = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let resource = Data([0, 255, 42, 13])
        try contents.write(to: source.appendingPathComponent("contents.xml"))
        try resource.write(to: source.appendingPathComponent("assets/icon.bin"))
        try MindNodePackage.copyUnmodified(from: source, to: output)
        assert((try? Data(contentsOf: output.appendingPathComponent("contents.xml"))) == contents)
        assert((try? Data(contentsOf: output.appendingPathComponent("assets/icon.bin"))) == resource)
        assert((try? Data(contentsOf: source.appendingPathComponent("contents.xml"))) == contents)
        assert((try? Data(contentsOf: source.appendingPathComponent("assets/icon.bin"))) == resource)
        assert((try? MindNodeImporter.load(output).first?.title) == "合成节点")
        let staged = try fm.contentsOfDirectory(atPath: scratch.path)
        assert(!staged.contains { $0.hasPrefix(".mindmap-copy-") })
        let edited = MapNode(id: rootID, title: "改过 <&> 🧭", children: [], folded: true)
        let updatedOutput = scratch.appendingPathComponent("edited.mindnode", isDirectory: true)
        let proposed = try MindNodeTitlePatch.apply(to: contents, original: MindNodeImporter.load(source), edited: [edited])
        assert(proposed != contents)
        try MindNodePackage.copyUpdatingExistingNodes(from: source, to: updatedOutput, editedRoots: [edited])
        let imported = try MindNodeImporter.load(updatedOutput)
        assert(imported.count == 1 && imported[0].id == rootID)
        assert(imported[0].title == edited.title && imported[0].folded)
        assert((try? Data(contentsOf: updatedOutput.appendingPathComponent("assets/icon.bin"))) == resource)
        assert((try? Data(contentsOf: source.appendingPathComponent("contents.xml"))) == contents)
        var updatedFormat = PropertyListSerialization.PropertyListFormat.binary
        let updatedPlist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: updatedOutput.appendingPathComponent("contents.xml")),
            options: [], format: &updatedFormat) as! [String: Any]
        assert((updatedPlist["unknownRootField"] as? [Int]) == [1, 2, 3])
        let updatedRoot = ((updatedPlist["canvas"] as! [String: Any])["mindMaps"] as! [[String: Any]])[0]["mainNode"] as! [String: Any]
        assert(((updatedRoot["unknownNodeField"] as! [String: Any])["color"] as? String) == "preserve")
        func rejects(_ block: () throws -> Void) -> Bool {
            do { try block(); return false } catch { return true }
        }
        let secondID = UUID()
        let styled: [String: Any] = ["nodeID": secondID.uuidString,
                                     "title": ["text": "<p>Styled <b>untouched</b></p>", "opaqueStyle": "keep"],
                                     "subnodes": [], "hasFoldedSubnodes": false,
                                     "notes": ["text": "synthetic note", "attachment": "assets/note.bin"]]
        let maps: [[String: Any]] = [["mainNode": root], ["mainNode": styled, "unknownMapKey": 73]]
        let mixedPlist: [String: Any] = ["version": 9, "canvas": ["mindMaps": maps], "unknownRootField": [1, 2, 3]]
        let mixedData = try PropertyListSerialization.data(fromPropertyList: mixedPlist, format: .binary, options: 0)
        let mixedSource = scratch.appendingPathComponent("multi.mindnode", isDirectory: true)
        try fm.createDirectory(at: mixedSource.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try mixedData.write(to: mixedSource.appendingPathComponent("contents.xml"))
        try resource.write(to: mixedSource.appendingPathComponent("assets/note.bin"))
        var mixedEdited = try MindNodeImporter.load(mixedSource)
        assert(mixedEdited.count == 2 && mixedEdited[1].title == "Styled untouched")
        mixedEdited[0].title = "多图 🔗"
        mixedEdited[0].folded = true
        let mixedOutput = scratch.appendingPathComponent("multi-edited.mindnode", isDirectory: true)
        try MindNodePackage.copyUpdatingExistingNodes(from: mixedSource, to: mixedOutput, editedRoots: mixedEdited)
        assert((try? MindNodeImporter.load(mixedOutput)) == mixedEdited)
        assert((try? Data(contentsOf: mixedOutput.appendingPathComponent("assets/note.bin"))) == resource)
        assert((try? Data(contentsOf: mixedSource.appendingPathComponent("contents.xml"))) == mixedData)
        assert((try? Data(contentsOf: mixedSource.appendingPathComponent("assets/note.bin"))) == resource)
        let mixedWritten = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: mixedOutput.appendingPathComponent("contents.xml")),
            options: [], format: nil) as! [String: Any]
        let writtenMaps = (mixedWritten["canvas"] as! [String: Any])["mindMaps"] as! [[String: Any]]
        assert((writtenMaps[1]["mainNode"] as! [String: Any])["notes"] as? [String: String] == ["text": "synthetic note", "attachment": "assets/note.bin"])
        let preservedTitle = (writtenMaps[1]["mainNode"] as! [String: Any])["title"] as? [String: String]
        assert(preservedTitle?["text"] == "<p>Styled <b>untouched</b></p>" && preservedTitle?["opaqueStyle"] == "keep")
        assert((writtenMaps[1]["unknownMapKey"] as? Int) == 73)
        var styleEdited = mixedEdited
        styleEdited[1].title = "Flattened"
        let styleRejected = scratch.appendingPathComponent("style-rejected.mindnode", isDirectory: true)
        assert(rejects { try MindNodePackage.copyUpdatingExistingNodes(from: mixedSource, to: styleRejected, editedRoots: styleEdited) })
        assert(!fm.fileExists(atPath: styleRejected.path))
        let removedRootOutput = scratch.appendingPathComponent("removed-root.mindnode", isDirectory: true)
        assert(rejects { try MindNodePackage.copyUpdatingExistingNodes(
            from: mixedSource, to: removedRootOutput, editedRoots: [mixedEdited[0]]) })
        assert(!fm.fileExists(atPath: removedRootOutput.path)) // Structural edits stay JSON-only.
        let emptySource = scratch.appendingPathComponent("empty.mindnode", isDirectory: true)
        try fm.createDirectory(at: emptySource, withIntermediateDirectories: false)
        let emptyData = try PropertyListSerialization.data(fromPropertyList: ["version": 9, "canvas": ["mindMaps": []]], format: .binary, options: 0)
        try emptyData.write(to: emptySource.appendingPathComponent("contents.xml"))
        let emptyOutput = scratch.appendingPathComponent("empty-copy.mindnode", isDirectory: true)
        try MindNodePackage.copyUpdatingExistingNodes(from: emptySource, to: emptyOutput, editedRoots: [])
        assert((try? Data(contentsOf: emptyOutput.appendingPathComponent("contents.xml"))) == emptyData)
        assert((try? MindNodeImporter.load(emptyOutput)) == [])
        assert(rejects { try MindNodePackage.copyUnmodified(from: source, to: output) }) // No replacement.
        assert(rejects { try MindNodePackage.copyUpdatingExistingNodes(from: source, to: updatedOutput, editedRoots: [edited]) })
        var structural = edited
        structural.children = [MapNode(id: UUID(), title: "new", children: [], folded: false)]
        let unsupported = scratch.appendingPathComponent("unsupported.mindnode", isDirectory: true)
        assert(rejects { try MindNodePackage.copyUpdatingExistingNodes(from: source, to: unsupported, editedRoots: [structural]) })
        assert(!fm.fileExists(atPath: unsupported.path))
        let hardlinkSource = scratch.appendingPathComponent("hardlink.mindnode", isDirectory: true)
        try fm.createDirectory(at: hardlinkSource, withIntermediateDirectories: false)
        let external = scratch.appendingPathComponent("external-contents.bin")
        try contents.write(to: external)
        try fm.linkItem(at: external, to: hardlinkSource.appendingPathComponent("contents.xml"))
        let hardlinkOutput = scratch.appendingPathComponent("hardlink-edited.mindnode", isDirectory: true)
        try MindNodePackage.copyUpdatingExistingNodes(from: hardlinkSource, to: hardlinkOutput, editedRoots: [edited])
        assert((try? MindNodeImporter.load(hardlinkOutput)) == [edited])
        let originalInode = try fm.attributesOfItem(atPath: external.path)[.systemFileNumber] as? NSNumber
        let copiedInode = try fm.attributesOfItem(atPath: hardlinkOutput.appendingPathComponent("contents.xml").path)[.systemFileNumber] as? NSNumber
        assert(originalInode != nil && copiedInode != nil && originalInode != copiedInode)
        assert((try? Data(contentsOf: external)) == contents, "Hard-linked outside file must never change")
        assert((try? Data(contentsOf: hardlinkSource.appendingPathComponent("contents.xml"))) == contents)
        let remaining = try fm.contentsOfDirectory(atPath: scratch.path)
        assert(!remaining.contains { $0.hasPrefix(".mindmap-copy-") })
        assert((try? Data(contentsOf: output.appendingPathComponent("contents.xml"))) == contents)
        assert(rejects { try MindNodePackage.copyUnmodified(from: source, to: source.appendingPathComponent("child.mindnode")) })
        let link = source.appendingPathComponent("external")
        try fm.createSymbolicLink(at: link, withDestinationURL: scratch.appendingPathComponent(".owner"))
        assert(rejects { try MindNodePackage.copyUnmodified(from: source, to: scratch.appendingPathComponent("bad.mindnode")) })
        assert(!fm.fileExists(atPath: scratch.appendingPathComponent("bad.mindnode").path))
        let malformed = scratch.appendingPathComponent("malformed.mindnode", isDirectory: true)
        try fm.createDirectory(at: malformed, withIntermediateDirectories: false)
        try Data([0x01]).write(to: malformed.appendingPathComponent("contents.xml"))
        let rejected = scratch.appendingPathComponent("rejected.mindnode", isDirectory: true)
        assert(rejects { try MindNodePackage.copyUnmodified(from: malformed, to: rejected) })
        assert(!fm.fileExists(atPath: rejected.path))
        let linkedSource = scratch.appendingPathComponent("alias.mindnode")
        try fm.createSymbolicLink(at: linkedSource, withDestinationURL: source)
        assert(rejects { try MindNodePackage.copyUnmodified(from: linkedSource, to: scratch.appendingPathComponent("alias-copy.mindnode")) })
        print("synthetic v9 edits, multi/empty maps, metadata, resources, collisions and symlinks passed; hardlink cloned without source writes")
    }
}
