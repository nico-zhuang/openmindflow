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
        var saved = try Data(contentsOf: url)
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
        let styled = OwnMapDocument(roots: roots, theme: "tropical", canvasColor: "#102030FF")
        var inspectorRoots = roots
        inspectorRoots[0].note = "Example note"
        inspectorRoots[0].rootShape = "rounded"
        inspectorRoots[0].rootFillColor = "#112233FF"
        try writeOwnDocument(OwnMapDocument(roots: inspectorRoots, theme: "tropical", canvasColor: "#102030FF"), to: url)
        assert((try? readOwnDocument(url).roots) == inspectorRoots)
        try writeOwnDocument(styled, to: url)
        let styledBytes = try Data(contentsOf: url)
        assert(styledBytes.first == UInt8(ascii: "{"))
        let reopenedStyled = try readOwnDocument(url)
        assert(reopenedStyled.roots == roots && reopenedStyled.relationships.isEmpty &&
               reopenedStyled.theme == "tropical" && reopenedStyled.canvasColor == "#102030FF")
        do { _ = try readOwnJSON(url); fatalError("Legacy read lost appearance") }
        catch OwnJSONError.requiresDocumentAPI { }
        do { try writeOwnJSON(roots, to: url); fatalError("Legacy write lost appearance") }
        catch OwnJSONError.requiresDocumentAPI { }
        assert((try? Data(contentsOf: url)) == styledBytes)
        var invalidStyled = styled
        invalidStyled.theme = "unknown"
        rejects { try writeOwnDocument(invalidStyled, to: url) }
        invalidStyled = styled
        invalidStyled.canvasColor = "not a color"
        rejects { try writeOwnDocument(invalidStyled, to: url) }
        invalidStyled = styled
        invalidStyled.roots[0].note = String(repeating: "é", count: 32_769)
        rejects { try writeOwnDocument(invalidStyled, to: url) }
        invalidStyled = styled
        invalidStyled.roots[0].rootShape = "ellipse"
        rejects { try writeOwnDocument(invalidStyled, to: url) }
        invalidStyled = styled
        invalidStyled.roots[0].rootFillColor = "bad"
        rejects { try writeOwnDocument(invalidStyled, to: url) }
        assert((try? Data(contentsOf: url)) == styledBytes)
        try writeOwnDocument(document, to: url)
        saved = try Data(contentsOf: url)
        var invalid = document
        invalid.relationships[0].to = UUID()
        rejects { try writeOwnDocument(invalid, to: url) }
        invalid.relationships = [edge, edge]
        rejects { try writeOwnDocument(invalid, to: url) }
        invalid.relationships = [edge]
        invalid.relationships[0].control1 = SIMD2(1_000_001, 0)
        rejects { try writeOwnDocument(invalid, to: url) }
        var badVideo = roots
        badVideo[0].videoWidth = 200
        rejects { try writeOwnDocument(OwnMapDocument(roots: badVideo, relationships: [edge]), to: url) }
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
