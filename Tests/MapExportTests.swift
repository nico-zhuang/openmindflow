import AppKit
import Darwin
import CoreGraphics
import ImageIO

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
        var noted = root
        noted.note = "Private context omitted from Markdown"
        let noteMarkdown = exportMarkdown([noted])
        assert(noteMarkdown.contains("Notes are not included in this Markdown export."))
        assert(!noteMarkdown.contains("Private context omitted"))
        func colorComponents(_ color: NSColor?) -> [CGFloat] {
            guard let rgb = color else { return [] }
            return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        }
        func close(_ actual: NSColor?, _ expected: NSColor, tolerance: CGFloat = 0.04) -> Bool {
            let a = colorComponents(actual), b = colorComponents(expected)
            return a.count == 3 && b.count == 3 && zip(a, b).allSatisfy { abs($0 - $1) < tolerance }
        }
        let small = MapCanvas(model: MapModel(roots: [MapNode(id: UUID(), title: "Ink", children: [], folded: false)], selected: UUID()))
        small.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        small.appearance = NSAppearance(named: .aqua)
        func screenCorner() -> NSColor? {
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
            small.effectiveAppearance.performAsCurrentDrawingAppearance { small.draw(small.bounds) }
            NSGraphicsContext.current = previous
            return image.colorAt(x: 0, y: 0)
        }
        func pdfCorner(_ bytes: Data) -> NSColor? {
            guard let page = CGPDFDocument(CGDataProvider(data: bytes as CFData)!)?.page(at: 1) else { return nil }
            let rect = page.getBoxRect(.mediaBox)
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: image)!.cgContext
            context.drawPDFPage(page)
            context.flush()
            return image.colorAt(x: 0, y: 0)
        }
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
          small.appearance = NSAppearance(named: appearance)
          for hex in ["#102030FF", "#10203080"] {
            assert(small.model.setCanvasColor(hex))
            var system = NSColor.white
            small.effectiveAppearance.performAsCurrentDrawingAppearance {
                system = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? .white
            }
            let foreground = NSColor(srgbRed: 16/255, green: 32/255, blue: 48/255,
                                     alpha: hex.hasSuffix("80") ? 128/255 : 1)
            let alpha = foreground.alphaComponent
            let expected = NSColor(srgbRed: foreground.redComponent * alpha + system.redComponent * (1 - alpha),
                green: foreground.greenComponent * alpha + system.greenComponent * (1 - alpha),
                blue: foreground.blueComponent * alpha + system.blueComponent * (1 - alpha), alpha: 1)
            assert(close(screenCorner(), expected), "Screen backdrop must composite over effective system appearance")
            for (format, suffix) in [(MapExportFormat.png, "png"), (.jpeg, "jpg"), (.pdf, "pdf")] {
                let output = scratch.appendingPathComponent("canvas-\(appearance.rawValue)-\(hex)-\(suffix).\(suffix)")
                try exportMap(small, as: format, to: output)
                let bytes = try Data(contentsOf: output)
                let corner = format == .pdf ? pdfCorner(bytes) : NSBitmapImageRep(data: bytes)?.colorAt(x: 0, y: 0)
                assert(close(corner, expected, tolerance: format == .jpeg ? 0.07 : 0.04),
                       "\(appearance.rawValue) \(hex) \(suffix) canvas differs from screen: \(colorComponents(corner)) vs \(colorComponents(expected))")
            }
          }
        }
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
        var pdfSize = CGSize.zero
        var rasterPaths: [MapExportFormat: URL] = [:]
        for (format, name) in [(MapExportFormat.png, "whole.png"), (.jpeg, "whole.jpg"), (.pdf, "whole.pdf"), (.markdown, "whole.md")] {
            let output = scratch.appendingPathComponent(name)
            try exportMap(canvas, as: format, to: output)
            let bytes = try Data(contentsOf: output)
            assert(bytes.count > 30)
            if format == .pdf {
                guard let document = CGPDFDocument(CGDataProvider(data: bytes as CFData)!), let page = document.page(at: 1) else {
                    fatalError("Not a PDF")
                }
                pdfSize = page.getBoxRect(.mediaBox).size
                assert(pdfSize.width > 1_800 && pdfSize.height > 850)
            } else if format != .markdown {
                rasterPaths[format] = output
                guard let bitmap = NSBitmapImageRep(data: bytes) else { fatalError("Not an image") }
                assert(bitmap.pixelsWide > 1_800 && bitmap.pixelsHigh > 850)
                let corner = bitmap.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
                assert(corner.redComponent > 0.7 && corner.alphaComponent > 0.99)
            }
            do { try exportMap(canvas, as: format, to: output); fatalError("Overwrote existing export") }
            catch MapExportError.destinationExists { }
        }
        for format in [MapExportFormat.png, .jpeg] {
            let path = rasterPaths[format]!
            let bytes = try Data(contentsOf: path)
            let bitmap = NSBitmapImageRep(data: bytes)!
            assert(abs(CGFloat(bitmap.pixelsWide) - pdfSize.width * 2) < 3)
            assert(abs(CGFloat(bitmap.pixelsHigh) - pdfSize.height * 2) < 3)
            assert(abs(bitmap.size.width - pdfSize.width) < 3)
            assert(abs(bitmap.size.height - pdfSize.height) < 3)
            let source = CGImageSourceCreateWithData(bytes as CFData, nil)!
            let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
            let dpiX = metadata[kCGImagePropertyDPIWidth] as? NSNumber
            let dpiY = metadata[kCGImagePropertyDPIHeight] as? NSNumber
            assert((140...148).contains(dpiX?.doubleValue ?? 0))
            assert((140...148).contains(dpiY?.doubleValue ?? 0))
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
        let importedPDF = scratch.appendingPathComponent("imported-far.pdf")
        try exportMap(importedCanvas, as: .pdf, to: importedPDF)
        let importedPage = CGPDFDocument(CGDataProvider(data: try Data(contentsOf: importedPDF) as CFData)!)!.page(at: 1)!
        let importedPoints = importedPage.getBoxRect(.mediaBox).size
        let importedScale = CGFloat(importedImage.pixelsWide) / importedPoints.width
        assert(importedScale >= 1 && importedScale < 2)
        assert(importedImage.pixelsWide <= 8192 && importedImage.pixelsHigh <= 8192)
        assert(importedImage.pixelsWide * importedImage.pixelsHigh <= 32_000_000)
        assert(abs(importedImage.size.width - importedPoints.width) < 3)
        // Mixed, imported nil-side frames must set detached export bounds (not a fresh default layout).
        var mixedLeft = MapNode(id: UUID(), title: "LEFT NOTE", children: [], folded: false)
        mixedLeft.note = "Left context"
        mixedLeft.branchStrokeColor = "#FF2020FF"
        var mixedRight = MapNode(id: UUID(), title: "RIGHT NOTE", children: [], folded: false)
        mixedRight.note = "Right context"
        mixedRight.branchStrokeColor = "#2020FFFF"
        let mixedRoot = MapNode(id: UUID(), title: "MIXED ROOT", children: [mixedLeft, mixedRight], folded: false)
        let mixedModel = MapModel(roots: [mixedRoot], selected: mixedRoot.id)
        let mixed = MapCanvas(model: mixedModel)
        mixed.frame = CGRect(x: 0, y: 0, width: 500, height: 400)
        mixed.appearance = NSAppearance(named: .aqua)
        mixed.nativePresentation[mixedRoot.id] = MindNodePresentation(location: CGPoint(x: 100, y: 100),
            maxWidth: nil, allowToShrinkWidth: nil, font: nil, styleChangedByUser: nil, fillColor: nil)
        mixed.nativePresentation[mixedLeft.id] = MindNodePresentation(location: CGPoint(x: -1700, y: 120),
            maxWidth: nil, allowToShrinkWidth: nil, font: nil, styleChangedByUser: nil, fillColor: nil)
        mixed.nativePresentation[mixedRight.id] = MindNodePresentation(location: CGPoint(x: 1700, y: 120),
            maxWidth: nil, allowToShrinkWidth: nil, font: nil, styleChangedByUser: nil, fillColor: nil)
        let originals = mixedModel.roots
        let originalPresentation = mixed.nativePresentation
        let mixedSource = scratch.appendingPathComponent("mixed-source.mindmap.json")
        try writeOwnJSON(originals, to: mixedSource)
        let mixedSourceBytes = try Data(contentsOf: mixedSource)
        let mixedFrames = [mixedRoot.id, mixedLeft.id, mixedRight.id].map { mixed.frameForAccessibility($0)! }
        let mixedExtent = mixedFrames.reduce(CGRect.null) { $0.union($1) }
        var mixedPDFSize = CGSize.zero
        for (format, name) in [(MapExportFormat.png, "mixed.png"), (.pdf, "mixed.pdf"), (.jpeg, "mixed.jpg")] {
            let output = scratch.appendingPathComponent(name)
            try exportMap(mixed, as: format, to: output)
            let bytes = try Data(contentsOf: output)
            if format == .pdf {
                let document = CGPDFDocument(CGDataProvider(data: bytes as CFData)!)!
                mixedPDFSize = document.page(at: 1)!.getBoxRect(.mediaBox).size
                assert(mixedPDFSize.width >= mixedExtent.width + 100 && mixedPDFSize.height >= mixedExtent.height + 100,
                       "Mixed imported left/right PDF MediaBox must include full world bounds plus margin")
            } else {
                let raster = NSBitmapImageRep(data: bytes)!
                assert(raster.pixelsWide >= Int(mixedExtent.width + 100) && raster.pixelsHigh >= Int(mixedExtent.height + 100),
                       "Mixed imported left/right \(name) raster must include full world bounds")
                var leftInk = false, rightInk = false
                for x in stride(from: 0, to: raster.pixelsWide, by: 2) {
                    for y in stride(from: 0, to: raster.pixelsHigh, by: 2) {
                        guard let pixel = raster.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        if pixel.redComponent > 0.7 && pixel.greenComponent < 0.4 && pixel.blueComponent < 0.4 && x < raster.pixelsWide / 3 { leftInk = true }
                        if pixel.blueComponent > 0.7 && pixel.greenComponent < 0.4 && pixel.redComponent < 0.4 && x > raster.pixelsWide * 2 / 3 { rightInk = true }
                    }
                }
                assert(leftInk && rightInk, "Both explicitly colored, noted side branches must render without clipping in \(name)")
                if format == .jpeg {
                    assert(abs(CGFloat(raster.pixelsWide) - mixedPDFSize.width * 2) < 3 ||
                           CGFloat(raster.pixelsWide) / mixedPDFSize.width >= 1,
                           "JPEG scale can be capped but must not shrink below one pixel per PDF point")
                }
            }
        }
        let mixedAfter = try Data(contentsOf: mixedSource)
        let notedPNG = NSBitmapImageRep(data: try Data(contentsOf: scratch.appendingPathComponent("mixed.png")))!
        assert(mixedModel.setNote("", for: mixedLeft.id) && mixedModel.setNote("", for: mixedRight.id))
        let noNotesOutput = scratch.appendingPathComponent("mixed-without-notes.png")
        try exportMap(mixed, as: .png, to: noNotesOutput)
        let noNotesPNG = NSBitmapImageRep(data: try Data(contentsOf: noNotesOutput))!
        assert(notedPNG.pixelsWide == noNotesPNG.pixelsWide && notedPNG.pixelsHigh == noNotesPNG.pixelsHigh)
        var leftNoteInk = false, rightNoteInk = false
        for x in 0..<notedPNG.pixelsWide {
            for y in 0..<notedPNG.pixelsHigh {
                guard let a = notedPNG.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let b = noNotesPNG.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let changed = abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) > 0.2
                if changed && x < notedPNG.pixelsWide / 3 { leftNoteInk = true }
                if changed && x > notedPNG.pixelsWide * 2 / 3 { rightNoteInk = true }
            }
        }
        assert(leftNoteInk && rightNoteInk, "Detached PNG must paint both left and right child note-paper ink")
        assert(mixedModel.setNote("Left context", for: mixedLeft.id) && mixedModel.setNote("Right context", for: mixedRight.id))
        assert(mixedModel.roots == originals && mixedAfter == mixedSourceBytes &&
               mixed.nativePresentation.count == originalPresentation.count &&
               mixed.nativePresentation[mixedLeft.id]?.location == originalPresentation[mixedLeft.id]?.location &&
               mixed.nativePresentation[mixedRight.id]?.location == originalPresentation[mixedRight.id]?.location,
               "Detached exports cannot mutate model, imported frames or source bytes")
        // Explicit left direction must survive own-document save/reopen before all three exports.
        var explicitLeft = mixedLeft
        explicitLeft.branchSide = "left"
        let explicitRoot = MapNode(id: UUID(), title: "EXPLICIT ROOT",
                                   children: [explicitLeft, mixedRight], folded: false)
        let explicitSource = scratch.appendingPathComponent("explicit-left.mindmap.json")
        try writeOwnJSON([explicitRoot], to: explicitSource)
        let explicitBytes = try Data(contentsOf: explicitSource)
        let reopened = try readOwnJSON(explicitSource)
        assert(reopened == [explicitRoot] && reopened[0].children[0].branchSide == "left" &&
               reopened[0].children[1].branchSide == nil)
        let explicitModel = MapModel(roots: reopened, selected: reopened[0].id)
        let explicitCanvas = MapCanvas(model: explicitModel)
        explicitCanvas.frame = CGRect(x: 0, y: 0, width: 500, height: 400)
        explicitCanvas.appearance = NSAppearance(named: .aqua)
        let explicitLeftFrame = explicitCanvas.frameForAccessibility(explicitLeft.id)!
        let explicitRightFrame = explicitCanvas.frameForAccessibility(mixedRight.id)!
        let explicitRootFrame = explicitCanvas.frameForAccessibility(explicitRoot.id)!
        assert(explicitLeftFrame.maxX <= explicitRootFrame.minX - 60 &&
               explicitRightFrame.minX >= explicitRootFrame.maxX + 60)
        let explicitExtent = [explicitLeftFrame, explicitRightFrame, explicitRootFrame]
            .reduce(CGRect.null) { $0.union($1) }
        for (format, name) in [(MapExportFormat.png, "explicit-left.png"),
                               (.pdf, "explicit-left.pdf"), (.jpeg, "explicit-left.jpg")] {
            let output = scratch.appendingPathComponent(name)
            try exportMap(explicitCanvas, as: format, to: output)
            let bytes = try Data(contentsOf: output)
            if format == .pdf {
                let page = CGPDFDocument(CGDataProvider(data: bytes as CFData)!)!.page(at: 1)!
                let size = page.getBoxRect(.mediaBox).size
                assert(size.width >= explicitExtent.width + 100 && size.height >= explicitExtent.height + 100,
                       "Reopened explicit left/right PDF must contain both sides")
            } else {
                let raster = NSBitmapImageRep(data: bytes)!
                assert(raster.pixelsWide >= Int(explicitExtent.width + 100) &&
                       raster.pixelsHigh >= Int(explicitExtent.height + 100),
                       "Reopened explicit left/right raster must contain both sides")
                var leftInk = false, rightInk = false
                for x in stride(from: 0, to: raster.pixelsWide, by: 2) {
                    for y in stride(from: 0, to: raster.pixelsHigh, by: 2) {
                        guard let pixel = raster.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        if pixel.redComponent > 0.7 && pixel.greenComponent < 0.4 &&
                           pixel.blueComponent < 0.4 && x < raster.pixelsWide / 3 { leftInk = true }
                        if pixel.blueComponent > 0.7 && pixel.greenComponent < 0.4 &&
                           pixel.redComponent < 0.4 && x > raster.pixelsWide * 2 / 3 { rightInk = true }
                    }
                }
                assert(leftInk && rightInk, "Reopened explicit left/right inks must survive \(name)")
            }
        }
        let explicitAfterBytes = try Data(contentsOf: explicitSource)
        assert(explicitModel.roots == reopened && explicitAfterBytes == explicitBytes,
               "Reopened left/right exports must not modify model or saved document")
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
