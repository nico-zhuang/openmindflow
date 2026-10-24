import AppKit
import Darwin
import CoreGraphics

@main
enum MapExportTests {
    static func main() throws {
        _ = NSApplication.shared // No window, original app, or global events.
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/map-export-XXXXXX").utf8CString
        let path = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let created = mkdtemp(start) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return String(cString: created)
        }
        let scratch = URL(fileURLWithPath: path, isDirectory: true)
        var info = stat()
        guard scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
              scratch.deletingLastPathComponent() == base,
              lstat(scratch.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Unsafe test directory") }
        defer { try? fm.removeItem(at: scratch) }

        var root = MapNode(id: UUID(), title: "Root *plan*", children: [], folded: false)
        var far = MapNode(id: UUID(), title: "Far\nchild <&>", children: [
            MapNode(id: UUID(), title: "Hidden [leaf]", children: [], folded: false)
        ], folded: true)
        root.location = SIMD2<Double>(100, 100)
        far.location = SIMD2<Double>(1900, 900)
        root.children = [far]
        let model = MapModel(roots: [root], selected: root.id)
        let canvas = MapCanvas(model: model)
        canvas.appearance = NSAppearance(named: .aqua)
        canvas.frame = CGRect(x: 0, y: 0, width: 320, height: 240)
        let viewport = canvas.frameForAccessibility(root.id)
        let source = scratch.appendingPathComponent("source.mindmap.json")
        try writeOwnJSON(model.roots, to: source)
        let sourceBytes = try Data(contentsOf: source)

        assert(exportMarkdown(model.roots) == "- Root \\*plan\\*\n  - Far<br>child &lt;&amp;&gt;\n    - Hidden \\[leaf\\]\n")
        let pictureRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 12,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: pictureRep)
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 12, height: 12).fill()
        NSGraphicsContext.restoreGraphicsState()
        var imageOnly = MapNode(id: UUID(), title: "", children: [], folded: false)
        imageOnly.image = try MapImage(data: pictureRep.representation(using: .png, properties: [:])!)
        let imageMarkdown = exportMarkdown([imageOnly])
        assert(imageMarkdown == "> Images and other media are not embedded in this Markdown export.\n\n- [Image omitted]\n")
        assert(!imageMarkdown.contains("file://"))
        let imageCanvas = MapCanvas(model: MapModel(roots: [imageOnly], selected: imageOnly.id))
        let pictureOutput = scratch.appendingPathComponent("embedded-image.png")
        try exportMap(imageCanvas, as: .png, to: pictureOutput)
        let pictureBytes = try Data(contentsOf: pictureOutput)
        let exportedPicture = NSBitmapImageRep(data: pictureBytes)!
        let hasRedMediaPixel = (0..<exportedPicture.pixelsWide).contains { x in
            (0..<exportedPicture.pixelsHigh).contains { y in
                guard let color = exportedPicture.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return color.redComponent > 0.7 && color.greenComponent < 0.3 && color.blueComponent < 0.3
            }
        }
        assert(hasRedMediaPixel, "Embedded image must be drawn in the exported full map")
        for (format, name) in [(MapExportFormat.png, "whole.png"), (.jpeg, "whole.jpg"), (.pdf, "whole.pdf"), (.markdown, "whole.md")] {
            let output = scratch.appendingPathComponent(name)
            try exportMap(canvas, as: format, to: output)
            let bytes = try Data(contentsOf: output)
            assert(bytes.count > 30)
            if format == .pdf {
                guard let document = CGPDFDocument(CGDataProvider(data: bytes as CFData)!), let page = document.page(at: 1) else {
                    fatalError("Not a PDF")
                }
                assert(page.getBoxRect(.mediaBox).width > 1_800 && page.getBoxRect(.mediaBox).height > 850)
            } else if format != .markdown {
                guard let bitmap = NSBitmapImageRep(data: bytes) else { fatalError("Not an image") }
                assert(bitmap.pixelsWide > 1_800 && bitmap.pixelsHigh > 850)
                let corner = bitmap.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
                assert(corner.redComponent > 0.7 && corner.alphaComponent > 0.99)
            }
            do { try exportMap(canvas, as: format, to: output); fatalError("Overwrote existing export") }
            catch MapExportError.destinationExists { }
        }
        var importedRoot = root
        importedRoot.children[0].location = nil // Import metadata is authoritative only without saved own-JSON location.
        let importedCanvas = MapCanvas(model: MapModel(roots: [importedRoot], selected: root.id))
        importedCanvas.nativePresentation[far.id] = MindNodePresentation(location: CGPoint(x: 5_400, y: 1_500),
            maxWidth: nil, allowToShrinkWidth: nil, font: nil, styleChangedByUser: nil, fillColor: nil)
        let importedOutput = scratch.appendingPathComponent("imported-far.png")
        try exportMap(importedCanvas, as: .png, to: importedOutput)
        let importedBytes = try Data(contentsOf: importedOutput)
        let importedImage = NSBitmapImageRep(data: importedBytes)!
        assert(importedImage.pixelsWide > 5_000 && importedImage.pixelsHigh > 1_450)
        canvas.appearance = NSAppearance(named: .darkAqua)
        let darkOutput = scratch.appendingPathComponent("dark.jpg")
        try exportMap(canvas, as: .jpeg, to: darkOutput)
        let darkImage = NSBitmapImageRep(data: try Data(contentsOf: darkOutput))!
        let darkCorner = darkImage.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        assert(darkCorner.redComponent < 0.5 && darkCorner.alphaComponent > 0.99)
        let package = scratch.appendingPathComponent("source.mindnode", isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: false)
        do { try exportMap(canvas, as: .png, to: package.appendingPathComponent("image.png")); fatalError("Wrote inside .mindnode") }
        catch MapExportError.invalidDestination { }
        do { try exportMap(canvas, as: .pdf, to: scratch.appendingPathComponent("wrong.png")); fatalError("Accepted suffix mismatch") }
        catch MapExportError.invalidDestination { }
        assert(model.roots == [root] && canvas.frameForAccessibility(root.id) == viewport)
        let sourceAfter = try Data(contentsOf: source)
        let sourceRoots = try readOwnJSON(source)
        assert(sourceAfter == sourceBytes && sourceRoots == [root])
        let names = try fm.contentsOfDirectory(atPath: scratch.path)
        assert(!names.contains { $0.hasPrefix(".map-export-") })
        print("full-map PDF/PNG/JPEG and Markdown export tests passed (offscreen only)")
    }
}
