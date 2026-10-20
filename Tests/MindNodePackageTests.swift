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
        let root: [String: Any] = ["nodeID": UUID().uuidString,
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
        func rejects(_ block: () throws -> Void) -> Bool {
            do { try block(); return false } catch { return true }
        }
        assert(rejects { try MindNodePackage.copyUnmodified(from: source, to: output) }) // No replacement.
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
        print("synthetic v9 copy, resources, collisions and symlinks passed")
    }
}
