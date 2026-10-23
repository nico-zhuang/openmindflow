import Foundation
import Darwin

@main
enum MindNodeImporterTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let scratch = base.appendingPathComponent("mindmap-import-tests-\(UUID().uuidString)", isDirectory: true)
        let package = scratch.appendingPathComponent("fixture.mindnode", isDirectory: true)
        let single = scratch.appendingPathComponent("single.mindnode")
        let baseFD = open(base.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        precondition(baseFD >= 0)
        precondition(mkdirat(baseFD, scratch.lastPathComponent, 0o700) == 0) // Atomic exclusive create.
        let scratchFD = openat(baseFD, scratch.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        precondition(scratchFD >= 0 && mkdirat(scratchFD, "fixture.mindnode", 0o700) == 0)
        let packageFD = openat(scratchFD, "fixture.mindnode", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        precondition(packageFD >= 0)
        let inode = try fm.attributesOfItem(atPath: scratch.path)[.systemFileNumber] as? NSNumber
        let owner = UUID().uuidString
        let marker = scratch.appendingPathComponent(".test-owner")
        try owner.write(to: marker, atomically: true, encoding: .utf8)
        defer {
            let resolved = scratch.resolvingSymlinksInPath().standardizedFileURL
            let current = try? fm.attributesOfItem(atPath: scratch.path)[.systemFileNumber] as? NSNumber
            let stored = try? String(contentsOf: marker, encoding: .utf8)
            if resolved == scratch.standardizedFileURL, resolved.deletingLastPathComponent() == base,
               scratch.lastPathComponent.hasPrefix("mindmap-import-tests-"),
               inode != nil, current == inode, stored == owner {
                // Nonrecursive, descriptor-relative cleanup: another directory's contents cannot be removed.
                _ = unlinkat(packageFD, "contents.xml", 0)
                _ = unlinkat(scratchFD, "single.mindnode", 0)
                _ = unlinkat(scratchFD, ".test-owner", 0)
                _ = unlinkat(scratchFD, "fixture.mindnode", AT_REMOVEDIR)
                _ = unlinkat(baseFD, scratch.lastPathComponent, AT_REMOVEDIR)
            }
            _ = close(packageFD)
            _ = close(scratchFD)
            _ = close(baseFD)
        }
        do {
            _ = try MindNodeImporter.load(package)
            fputs("An empty MindNode package must not import\n", stderr); exit(1)
        } catch ImportError.missingContents {
            guard ImportError.missingContents.localizedDescription.contains("contents.xml") else {
                fputs("Missing package payload diagnostic must name contents.xml\n", stderr); exit(1)
            }
        } catch {
            fputs("A package missing contents.xml needs its own importer error\n", stderr); exit(1)
        }
        let rootID = UUID(), childID = UUID()
        let child: [String: Any] = ["nodeID": childID.uuidString, "title": ["text": "<p>Hello &amp; world</p>"], "subnodes": [], "hasFoldedSubnodes": true]
        let root: [String: Any] = ["nodeID": rootID.uuidString, "title": ["text": "<p>Root</p>"], "subnodes": [child], "hasFoldedSubnodes": false]
        func write(_ maps: [[String: Any]], version: Any = 9, format: PropertyListSerialization.PropertyListFormat = .binary) throws {
            let plist: [String: Any] = ["version": version, "canvas": ["mindMaps": maps.map { ["mainNode": $0] }]]
            try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
                .write(to: package.appendingPathComponent("contents.xml"), options: .atomic)
        }
        func rejects() -> Bool { (try? MindNodeImporter.load(package)) == nil }
        try write([root])
        let nodes = try MindNodeImporter.load(package)
        try Data(contentsOf: package.appendingPathComponent("contents.xml")).write(to: single, options: .atomic)
        #if HEADLESS_TEST
        let picker = AppDelegate()
        guard picker.panel(NSObject(), shouldEnable: single),
              (try? picker.panel(NSObject(), validate: single)) != nil,
              picker.panel(NSObject(), shouldEnable: package) else {
            fputs("Native picker must permit the synthetic v9 file and existing directory package\n", stderr); exit(1)
        }
        #endif
        guard (try? MindNodeImporter.load(single)) == nodes else {
            fputs("A direct .mindnode v9 binary plist must import exactly like contents.xml\n", stderr); exit(1)
        }
        assert(nodes.count == 1 && nodes[0].id == rootID && nodes[0].title == "Root")
        assert(nodes[0].children.count == 1 && nodes[0].children[0].id == childID)
        assert(nodes[0].children[0].title == "Hello & world" && nodes[0].children[0].folded)
        try Data([0x50, 0x4b, 0x03, 0x04, 0, 0]).write(to: single, options: .atomic)
        do {
            _ = try MindNodeImporter.load(single)
            fputs("A ZIP .mindnode must not be extracted or imported\n", stderr); exit(1)
        } catch ImportError.zipArchive {
            guard ImportError.zipArchive.localizedDescription.contains("ZIP") else {
                fputs("ZIP rejection must explain the unsupported container\n", stderr); exit(1)
            }
        } catch {
            fputs("ZIP input must return the explicit unsupported-container error\n", stderr); exit(1)
        }
        try write([root], version: 10)
        try Data(contentsOf: package.appendingPathComponent("contents.xml")).write(to: single, options: .atomic)
        do {
            _ = try MindNodeImporter.load(single)
            fputs("A newer direct plist must not be misreported as v9\n", stderr); exit(1)
        } catch ImportError.unsupported {
            guard ImportError.unsupported.localizedDescription.contains("v9") else {
                fputs("Unknown version diagnostic must identify the supported v9 boundary\n", stderr); exit(1)
            }
        } catch {
            fputs("Newer direct plist must return unsupported-version guidance\n", stderr); exit(1)
        }
        try Data(repeating: 0, count: 8 * 1024 * 1024 + 1).write(to: single, options: .atomic)
        do {
            _ = try MindNodeImporter.load(single)
            fputs("An oversized direct plist must never be parsed\n", stderr); exit(1)
        } catch ImportError.tooLarge {}
        let sparseFD = openat(scratchFD, "single.mindnode", O_WRONLY | O_NOFOLLOW)
        guard sparseFD >= 0, ftruncate(sparseFD, off_t(4_294_967_297)) == 0 else {
            if sparseFD >= 0 { _ = close(sparseFD) }
            fputs("Could not create owned sparse >4GiB size fixture\n", stderr); exit(1)
        }
        _ = close(sparseFD)
        do {
            _ = try MindNodeImporter.load(single)
            fputs("A >4GiB sparse direct plist must be rejected before reading\n", stderr); exit(1)
        } catch ImportError.tooLarge {}
        var decorated = root
        decorated["title"] = ["text": "<p>中文 &amp; emoji 🧭<br/>next line</p>"]
        decorated["notes"] = ["text": "Not copied"]
        decorated["attachments"] = [["file": "unused"]]
        try write([decorated])
        let special = try MindNodeImporter.load(package)
        assert(special[0].title == "中文 & emoji 🧭\nnext line")
        assert(special[0].children.count == 1)

        try write([])
        let empty = try MindNodeImporter.load(package)
        assert(empty.isEmpty)
        try Data([0x01, 0x02, 0x03]).write(to: package.appendingPathComponent("contents.xml"), options: .atomic)
        assert(rejects())
        try write([root], version: 8)
        assert(rejects())
        try write([root], version: 9.0) // A binary-plist real must not coerce to integer v9.
        assert(rejects())
        try write([root], version: true)
        assert(rejects())
        var numericFold = root
        numericFold["hasFoldedSubnodes"] = 1 // NSNumber(1) is not a plist Boolean.
        try write([numericFold])
        assert(rejects())
        try write([root], format: .xml)
        assert(rejects())
        var bad = root
        bad["title"] = ["text": "<p>broken"]
        try write([bad])
        do {
            _ = try MindNodeImporter.load(package)
            fputs("Invalid title data must not import\n", stderr); exit(1)
        } catch ImportError.invalid {
            guard ImportError.invalid.localizedDescription.contains("structure this v9 importer cannot read") else {
                fputs("Invalid v9 data must not imply the user's file itself is corrupt\n", stderr); exit(1)
            }
        } catch {
            fputs("A malformed known-v9 title needs the v9 structure diagnostic\n", stderr); exit(1)
        }
        bad["title"] = ["text": "<!DOCTYPE p [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]><p>&xxe;</p>"]
        try write([bad])
        assert(rejects())
        bad["title"] = ["text": "<p>Hi <b>there</b></p>"]
        try write([bad])
        let inline = try MindNodeImporter.load(package)
        assert(inline[0].title == "Hi there")
        bad["title"] = ["text": "<p><script>unknown</script></p>"]
        try write([bad])
        assert(rejects())
        bad["title"] = ["text": "<p>" + String(repeating: "<span>", count: 100) + "deep" + String(repeating: "</span>", count: 100) + "</p>"]
        try write([bad])
        assert(rejects())
        bad = root
        bad["subnodes"] = [root] // Duplicate UUID anywhere in the package is invalid.
        try write([bad])
        assert(rejects())
        try write([root, root]) // Duplicate IDs across separate maps are also invalid.
        assert(rejects())
        var deep: [String: Any] = child
        for _ in 0...201 {
            deep = ["nodeID": UUID().uuidString, "title": ["text": "<p>branch</p>"], "subnodes": [deep], "hasFoldedSubnodes": false]
        }
        try write([deep])
        assert(rejects())
        let wide: [[String: Any]] = (0...10_000).map { _ in
            ["nodeID": UUID().uuidString, "title": ["text": "<p>x</p>"], "subnodes": [], "hasFoldedSubnodes": false]
        }
        bad = root
        bad["subnodes"] = wide
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
