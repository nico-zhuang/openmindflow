import Foundation

@main
enum MindNodeImporterTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let scratch = base.appendingPathComponent("mindmap-import-tests-\(UUID().uuidString)", isDirectory: true)
        let package = scratch.appendingPathComponent("fixture.mindnode", isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        defer {
            // The only recursive delete in tests is the unique directory created above.
            let resolved = scratch.resolvingSymlinksInPath().standardizedFileURL
            if resolved.deletingLastPathComponent() == base && scratch.lastPathComponent.hasPrefix("mindmap-import-tests-") {
                try? fm.removeItem(at: scratch)
            }
        }
        let rootID = UUID(), childID = UUID()
        let child: [String: Any] = ["nodeID": childID.uuidString, "title": ["text": "<p>Hello &amp; world</p>"], "subnodes": [], "hasFoldedSubnodes": true]
        let root: [String: Any] = ["nodeID": rootID.uuidString, "title": ["text": "<p>Root</p>"], "subnodes": [child], "hasFoldedSubnodes": false]
        func write(_ maps: [[String: Any]], version: Int = 9, format: PropertyListSerialization.PropertyListFormat = .binary) throws {
            let plist: [String: Any] = ["version": version, "canvas": ["mindMaps": maps.map { ["mainNode": $0] }]]
            try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
                .write(to: package.appendingPathComponent("contents.xml"), options: .atomic)
        }
        func rejects() -> Bool { (try? MindNodeImporter.load(package)) == nil }
        try write([root])
        let nodes = try MindNodeImporter.load(package)
        assert(nodes.count == 1 && nodes[0].id == rootID && nodes[0].title == "Root")
        assert(nodes[0].children.count == 1 && nodes[0].children[0].id == childID)
        assert(nodes[0].children[0].title == "Hello & world" && nodes[0].children[0].folded)

        try write([])
        let empty = try MindNodeImporter.load(package)
        assert(empty.isEmpty)
        try Data([0x01, 0x02, 0x03]).write(to: package.appendingPathComponent("contents.xml"), options: .atomic)
        assert(rejects())
        try write([root], version: 8)
        assert(rejects())
        try write([root], format: .xml)
        assert(rejects())
        var bad = root
        bad["title"] = ["text": "<p>broken"]
        try write([bad])
        assert(rejects())
        bad["title"] = ["text": "<!DOCTYPE p [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]><p>&xxe;</p>"]
        try write([bad])
        assert(rejects())
        bad = root
        bad["subnodes"] = [root] // Duplicate UUID anywhere in the package is invalid.
        try write([bad])
        assert(rejects())
        try Data(repeating: 0, count: 8 * 1024 * 1024 + 1)
            .write(to: package.appendingPathComponent("contents.xml"), options: .atomic)
        assert(rejects())
        assert((try? MindNodeImporter.load(scratch)) == nil)
        print("import tests passed")
        if CommandLine.arguments.count > 1 {
            let imported = try MindNodeImporter.load(URL(fileURLWithPath: CommandLine.arguments[1]))
            func count(_ nodes: [MapNode]) -> Int { nodes.reduce(0) { $0 + 1 + count($1.children) } }
            print("authorized sample: maps=\(imported.count), nodes=\(count(imported))")
        }
    }
}
