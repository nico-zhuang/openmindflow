import AppKit
import Darwin

@main
enum OwnDocumentTests {
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let folder = base.appendingPathComponent("own-document-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        var info = stat()
        guard folder.deletingLastPathComponent() == base,
              folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
              lstat(folder.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { fatalError("Unsafe owned fixture path") }
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("map.mindmap.json")
        let left = UUID(), right = UUID()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = try MapImage(data: bitmap.representation(using: .png, properties: [:])!)
        let roots = [MapNode(id: left, title: "左图", children: [], folded: false, image: image),
                     MapNode(id: right, title: "Right", children: [], folded: false)]
        try writeOwnJSON(roots, to: url)
        let legacy = try readOwnDocument(url)
        assert(legacy.roots == roots && legacy.relationships.isEmpty)
        let oldBytes = try Data(contentsOf: url)
        assert(oldBytes.first == UInt8(ascii: "["))
        let edge = MapRelationship(from: left, to: right, style: .dashed)
        let document = OwnMapDocument(roots: roots, relationships: [edge])
        try writeOwnDocument(document, to: url)
        let saved = try Data(contentsOf: url)
        assert(saved.first == UInt8(ascii: "{"))
        let reopened = try readOwnDocument(url)
        assert(reopened.roots == roots && reopened.relationships == [edge])
        do { _ = try readOwnJSON(url); fatalError("Legacy roots-only reader must not discard relationships") }
        catch OwnJSONError.requiresDocumentAPI { }

        func rejects(_ operation: () throws -> Void) {
            do { try operation(); fatalError("Expected strict document rejection") }
            catch { }
        }
        do { try writeOwnJSON(roots, to: url); fatalError("Legacy save must not erase relationships") }
        catch OwnJSONError.requiresDocumentAPI { }
        let afterLegacySave = try Data(contentsOf: url)
        assert(afterLegacySave == saved)
        var invalid = document
        invalid.relationships[0].to = UUID()
        rejects { try writeOwnDocument(invalid, to: url) }
        invalid.relationships = [edge, edge]
        rejects { try writeOwnDocument(invalid, to: url) }
        invalid.relationships = [edge]
        invalid.relationships[0].control1 = SIMD2(1_000_001, 0)
        rejects { try writeOwnDocument(invalid, to: url) }
        let afterRejectedWrite = try Data(contentsOf: url)
        assert(afterRejectedWrite == saved, "Rejected write must leave previous file untouched")
        let bad = folder.appendingPathComponent("bad.mindmap.json")
        for edges in [[MapRelationship(from: left, to: UUID())], [edge, edge]] {
            let bytes = try JSONEncoder().encode(OwnMapDocument(roots: roots, relationships: edges))
            try bytes.write(to: bad)
            rejects { _ = try readOwnDocument(bad) }
        }
        var future = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        future["version"] = 2
        try JSONSerialization.data(withJSONObject: future).write(to: bad)
        rejects { _ = try readOwnDocument(bad) }
        try Data(count: MapModel.maxSavedJSONBytes + 1).write(to: bad)
        rejects { _ = try readOwnDocument(bad) }
        let package = folder.appendingPathComponent("synthetic.mindnode", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        rejects { try writeOwnDocument(document, to: package.appendingPathComponent("bad.mindmap.json")) }
        let linked = folder.appendingPathComponent("linked.mindmap.json")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: url)
        rejects { _ = try readOwnDocument(linked) }
        rejects { try writeOwnDocument(document, to: linked) }
        let final = try Data(contentsOf: url)
        assert(final == saved)
        print("versioned relationship document, legacy JSON, image, rejection and path tests passed")
    }
}
