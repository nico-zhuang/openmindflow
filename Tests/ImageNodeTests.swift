import AppKit
import ImageIO

@main
enum ImageNodeTests {
    static func main() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let image = try MapImage(data: png)
        assert(image.pixelWidth == 64 && image.pixelHeight == 32 && image.data == png)
        let jpeg = bitmap.representation(using: .jpeg, properties: [:])!
        let jpegImage = try MapImage(data: jpeg)
        assert(jpegImage.pixelWidth == 64)
        let parentID = UUID()
        let parent = MapNode(id: parentID, title: "Photos", children: [], folded: true,
                             fontFamily: "Helvetica", fontSize: 18)
        let insertion = MapModel(roots: [parent], selected: parentID)
        assert(insertion.addImageChild(image) && insertion.roots[0].children.count == 1)
        let inserted = insertion.roots[0].children[0]
        assert(!insertion.roots[0].folded && insertion.selected == inserted.id)
        assert(inserted.title.isEmpty && inserted.image == image && inserted.fontFamily == parent.fontFamily && inserted.fontSize == parent.fontSize)
        assert(insertion.undo() && insertion.roots == [parent] && insertion.selected == parentID,
               "Creating an image child is exactly one undo transaction")
        assert(insertion.redo() && insertion.roots[0].children[0].id == inserted.id)
        let rootID = UUID()
        let model = MapModel(roots: [MapNode(id: rootID, title: "", children: [], folded: false)], selected: rootID)
        assert(model.setImage(image) && model.roots[0].image == image)
        assert(model.setImageWidth(240) && model.roots[0].imageWidth == 240)
        assert(!model.setImageWidth(59) && !model.setImageWidth(1001) && !model.setImageWidth(.nan))
        let original = model.roots
        assert(model.undo() && model.roots[0].imageWidth == nil)
        assert(model.redo() && model.roots == original, "Rejected sizes must not clear redo")
        let emptyTitle = mapLayout(model.roots)[0].frame
        assert(emptyTitle.width >= 264 && emptyTitle.height >= 142, "Image-only nodes need visible image geometry")
        model.rename("Photo 🖼️")
        let titled = mapLayout(model.roots)[0].frame
        assert(titled.height > emptyTitle.height, "Optional image title needs its own text row")
        let positioned = mapLayout(model.roots, overrides: [rootID: MapLayoutOverride(
            location: CGPoint(x: 400, y: 200), maxWidth: 200, allowToShrinkWidth: true, font: nil)])[0].frame
        assert(positioned.midX == 400 && positioned.midY == 200 && positioned.height < titled.height,
               "A narrower native override scales the image proportionally around its saved center")

        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let folder = base.appendingPathComponent("image-node-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        guard folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
              folder.deletingLastPathComponent() == base else { fatalError("Unsafe scratch path") }
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("photos.mindmap.json")
        try writeOwnJSON(model.roots, to: url)
        let reopened = try readOwnJSON(url)
        assert(reopened == model.roots, "Image bytes, size and optional title survive JSON reopen")
        let existing = try Data(contentsOf: url)
        let legacy = try JSONDecoder().decode([MapNode].self, from: Data("[{\"id\":\"\(UUID())\",\"title\":\"Legacy\",\"children\":[],\"folded\":false}]".utf8))
        assert(legacy[0].image == nil)
        func rejects(_ action: () throws -> Void) {
            do { try action(); fatalError("Expected invalid image to be rejected") }
            catch { }
        }
        rejects { _ = try MapImage(data: Data()) }
        rejects { _ = try MapImage(data: Data(repeating: 0, count: 8 * 1024 * 1024 + 1)) }
        rejects { _ = try MapImage(data: Data("not an image".utf8)) }
        let corrupted = Data(png.prefix(12))
        rejects { _ = try MapImage(data: corrupted) }
        let unsafe = MapNode(id: UUID(), title: "Bad image size", children: [], folded: false,
                             image: image, imageWidth: 1001)
        rejects { try writeOwnJSON([unsafe], to: url) }
        let unchanged = try Data(contentsOf: url)
        assert(unchanged == existing, "Invalid image size must not overwrite saved map")
        let badURL = folder.appendingPathComponent("malformed.mindmap.json")
        try JSONEncoder().encode([unsafe]).write(to: badURL)
        rejects { _ = try readOwnJSON(badURL) }
        let damagedJSON = try JSONSerialization.data(withJSONObject: [[
            "id": UUID().uuidString, "title": "broken", "children": [], "folded": false,
            "image": ["data": Data("not an image".utf8).base64EncodedString()]
        ]])
        try damagedJSON.write(to: badURL)
        rejects { _ = try readOwnJSON(badURL) }
        let final = try readOwnJSON(url)
        assert(final == model.roots)
        print("image payload, undo, layout and bounded JSON tests passed")
    }
}
