import AppKit

@main enum BranchStyleTests {
    static func main() {
        guard mapFont(isRoot: false).fontName == "STSongti-SC-Regular",
              mapFont(isRoot: false).pointSize == 16,
              mapFont(isRoot: true).pointSize == 20 else {
            fputs("Node labels should use the original window's serif-style proportions, not the old 14pt system font\n", stderr)
            exit(1)
        }
        let child = MapNode(id: UUID(), title: "Branch", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Root", children: [child], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 900, height: 400)
        let nodes = mapLayout([root])
        func paint() -> NSBitmapImageRep {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 400,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0, bitsPerPixel: 0)!
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            canvas.effectiveAppearance.performAsCurrentDrawingAppearance { canvas.draw(canvas.bounds) }
            NSGraphicsContext.current = previous
            return bitmap
        }
        func rgba(_ color: NSColor?) -> [CGFloat] {
            guard let color = color?.usingColorSpace(.deviceRGB) else { return [] }
            return [color.redComponent, color.greenComponent, color.blueComponent]
        }
        func similar(_ a: NSColor?, _ b: NSColor?, tolerance: CGFloat = 0.025) -> Bool {
            let left = rgba(a), right = rgba(b)
            return left.count == 3 && right.count == 3 && zip(left, right).allSatisfy { abs($0 - $1) < tolerance }
        }
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            canvas.appearance = NSAppearance(named: appearance)
            let bitmap = paint()
            let blank = bitmap.colorAt(x: 3, y: 3)
            var systemBackground: NSColor = .windowBackgroundColor
            canvas.effectiveAppearance.performAsCurrentDrawingAppearance {
                systemBackground = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? .windowBackgroundColor
            }
            guard similar(blank, systemBackground) else {
                fputs("Canvas should use the system window background in both appearances\n", stderr); exit(1)
            }
            for item in nodes {
                let x = Int(item.frame.minX + 80 + 28)
                let top = Int(item.frame.minY + 90)
                let topPixel = bitmap.colorAt(x: x, y: bitmap.pixelsHigh - top - 1)
                guard (item.parent == nil) != similar(topPixel, blank) else {
                    fputs("Main/root nodes need a persistent shape; child labels alone stay borderless\n", stderr)
                    exit(1)
                }
            }
            let branch = nodes[1].frame
            let baseline = Int(branch.maxY + 90 - 7)
            let line = bitmap.colorAt(x: Int(branch.maxX + 80 - 18), y: bitmap.pixelsHigh - baseline - 1)
            guard !similar(line, blank) else {
                fputs("Branch label needs a visible horizontal line under its text\n", stderr); exit(1)
            }
        }
        var chain = MapNode(id: UUID(), title: "Level 5", children: [], folded: false)
        for depth in (1..<5).reversed() {
            chain = MapNode(id: UUID(), title: "Level \(depth)", children: [chain], folded: false)
        }
        let deepRoot = MapNode(id: UUID(), title: "Root", children: [chain], folded: false)
        let deepCanvas = MapCanvas(model: MapModel(roots: [deepRoot], selected: deepRoot.id))
        deepCanvas.frame = CGRect(x: 0, y: 0, width: 1800, height: 450)
        let strengths = mapLayout([deepRoot]).dropFirst().map { node -> CGFloat in
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 450,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0, bitsPerPixel: 0)!
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            deepCanvas.draw(deepCanvas.bounds)
            NSGraphicsContext.current = previous
            let x = Int(node.frame.maxX + 80 - 18), baseline = Int(node.frame.maxY + 90 - 7)
            let blank = rgba(bitmap.colorAt(x: 2, y: 2))
            return (-8...8).reduce(CGFloat(0)) { strength, dy in
                let sample = rgba(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - baseline - dy - 1))
                return strength + zip(sample, blank).map { abs($0 - $1) }.max()!
            }
        }
        guard zip(strengths, strengths.dropFirst()).allSatisfy({ $0 > $1 + 0.1 }) else {
            fputs("Every deeper branch stroke must taper visibly: \(strengths)\n", stderr); exit(1)
        }
        canvas.appearance = NSAppearance(named: .darkAqua)
        let fallback = paint()
        canvas.branchStyles = [child.id: MindNodeVisualStyle(rgba: [0.2, 0.7, 0.3, 1], width: 10)]
        let originalStyled = paint()
        let box = nodes[1].frame
        let x = Int(box.maxX + 80 - 18), baseline = Int(box.maxY + 90 - 7)
        let thickLine = originalStyled.colorAt(x: x, y: originalStyled.pixelsHigh - baseline + 4)
        let fallbackLine = fallback.colorAt(x: x, y: fallback.pixelsHigh - baseline + 4)
        guard !similar(thickLine, fallbackLine),
              similar(thickLine, NSColor(srgbRed: 0.2, green: 0.7, blue: 0.3, alpha: 1), tolerance: 0.08) else {
            fputs("An imported original v9 branch must use its own color and stroke width, not the fallback palette\n", stderr)
            exit(1)
        }
        canvas.selectAndEdit(child.id)
        guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first,
              !field.isBordered && !field.drawsBackground,
              canvas.frameForAccessibility(child.id) != nil else {
            fputs("Editing must keep invisible hit geometry without restoring a card or text-field box\n", stderr)
            exit(1)
        }
        print("borderless branch line, native editor, dark/light and AX hit geometry passed")
    }
}
