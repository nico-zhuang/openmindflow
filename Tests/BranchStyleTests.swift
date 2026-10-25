import AppKit

@main enum BranchStyleTests {
    static func main() {
        UserDefaults.standard.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        guard mapFont(isRoot: false).fontName == "STSongti-SC-Regular",
              mapFont(isRoot: false).pointSize == 20,
              mapFont(isRoot: true).pointSize == 24 else {
            fputs("Node labels should use the original window's serif-style proportions, not the old 14pt system font\n", stderr)
            exit(1)
        }
        let child = MapNode(id: UUID(), title: "Branch", children: [], folded: false)
        let nearbyChild = MapNode(id: UUID(), title: "Nearby", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Root", children: [child, nearbyChild], folded: false)
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
        let endCapX = Int(box.maxX + 80 + 3)
        let endCap = originalStyled.colorAt(x: endCapX, y: originalStyled.pixelsHigh - baseline - 1)
        guard similar(endCap, NSColor(srgbRed: 0.2, green: 0.7, blue: 0.3, alpha: 1), tolerance: 0.12) else {
            fputs("Branch line endpoints need smooth round caps, not squared-off cuts\n", stderr); exit(1)
        }
        canvas.selectNode(child.id)
        let selectedStyle = paint()
        let originalLine = originalStyled.colorAt(x: x, y: originalStyled.pixelsHigh - baseline - 1)
        let selectedLine = selectedStyle.colorAt(x: x, y: selectedStyle.pixelsHigh - baseline - 1)
        guard similar(selectedLine, originalLine, tolerance: 0.08) else {
            fputs("Selection must not recolor the original branch underline\n", stderr); exit(1)
        }
        let textBoxX = Int(box.minX + 80 + 8), textBoxY = Int(box.minY + 90 + 8)
        let unselectedBackdrop = originalStyled.colorAt(x: textBoxX, y: originalStyled.pixelsHigh - textBoxY - 1)
        let selectedBackdrop = selectedStyle.colorAt(x: textBoxX, y: selectedStyle.pixelsHigh - textBoxY - 1)
        guard !similar(selectedBackdrop, unselectedBackdrop) else {
            fputs("Selected child needs a highlight box around the text, not the underline\n", stderr); exit(1)
        }
        let plusX = Int(box.maxX + 80 + 15), plusY = Int(box.maxY + 90 - 7)
        let hiddenPlus = paint().colorAt(x: plusX, y: 400 - plusY - 1)
        let hover = NSEvent.mouseEvent(with: .mouseMoved,
            location: CGPoint(x: plusX, y: 400 - plusY), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
        canvas.mouseMoved(with: hover)
        let nearby = canvas.accessibilityChildren()?.compactMap { $0 as? NSAccessibilityElement }
            .filter { $0.accessibilityLabel() == "Add Child" } ?? []
        guard nearby.count >= 2 && nearby.count <= 3 else {
            fputs("Near a sibling cluster, show the nearest two or three add buttons rather than only one\n", stderr); exit(1)
        }
        let shownPlus = paint().colorAt(x: plusX, y: 400 - plusY - 1)
        guard !similar(hiddenPlus, shownPlus) else {
            fputs("Plus should appear only when the pointer approaches a branch endpoint\n", stderr); exit(1)
        }
        canvas.mouseExited(with: hover)
        let gonePlus = paint().colorAt(x: plusX, y: 400 - plusY - 1)
        guard similar(hiddenPlus, gonePlus) else {
            fputs("Plus must disappear when the pointer leaves the canvas\n", stderr); exit(1)
        }
        assert(canvas.model.setBranchStroke(width: 10, color: "#E10000FF", style: "dashed"))
        canvas.needsDisplay = true
        let custom = paint()
        let customY = custom.pixelsHigh - baseline - 1
        let samples = (Int(box.maxX + 80 - 65)..<Int(box.maxX + 80 - 5)).map {
            rgba(custom.colorAt(x: $0, y: customY))
        }
        let red = samples.filter { $0.count == 3 && $0[0] > 0.6 && $0[1] < 0.2 && $0[2] < 0.2 }.count
        guard red > 5 && red < samples.count - 5 else {
            fputs("Inspector stroke color and dashed style must render real colored gaps; red=\(red) total=\(samples.count) first=\(samples.first ?? []) last=\(samples.last ?? [])\n", stderr); exit(1)
        }
        assert(canvas.model.setAlignment("right"))
        canvas.needsDisplay = true
        canvas.selectAndEdit(child.id)
        guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first,
              field.alignment == .right && !field.isBordered && !field.drawsBackground,
              canvas.frameForAccessibility(child.id) != nil else {
            fputs("Editing must keep invisible hit geometry without restoring a card or text-field box\n", stderr)
            exit(1)
        }
        // Real paint, not inspector state: explicit node > selected palette > imported style.
        var themedRoot = root
        themedRoot.rootShape = "rectangle"
        let themed = MapCanvas(model: MapModel(roots: [themedRoot], selected: UUID()))
        themed.frame = canvas.frame
        themed.branchStyles = [child.id: MindNodeVisualStyle(rgba: [0.9, 0.1, 0.1, 1], width: 5),
                               nearbyChild.id: MindNodeVisualStyle(rgba: [0.1, 0.1, 0.9, 1], width: 5)]
        func paintTheme() -> NSBitmapImageRep {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 400,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            themed.effectiveAppearance.performAsCurrentDrawingAppearance { themed.draw(themed.bounds) }
            NSGraphicsContext.current = previous
            return bitmap
        }
        func branchPixel(_ bitmap: NSBitmapImageRep, _ item: LaidOutNode) -> NSColor? {
            let x = Int(item.frame.maxX + 80 - 18), y = Int(item.frame.maxY + 90 - 7)
            return bitmap.colorAt(x: x, y: bitmap.pixelsHigh - y - 1)
        }
        func rootTextPixels(_ bitmap: NSBitmapImageRep, _ box: CGRect) -> [[CGFloat]] {
            (Int(box.minX + 94)..<Int(box.maxX + 68)).flatMap { x in
                (Int(box.minY + 105)..<Int(box.maxY + 75)).map { y in
                    rgba(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - y - 1))
                }
            }
        }
        let imported = paintTheme()
        assert(similar(branchPixel(imported, nodes[1]), NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1), tolerance: 0.1))
        assert(similar(branchPixel(imported, nodes[2]), NSColor(srgbRed: 0.1, green: 0.1, blue: 0.9, alpha: 1), tolerance: 0.1))
        assert(themed.model.setTheme("rainbow"))
        themed.needsDisplay = true
        let rainbow = paintTheme()
        assert(similar(branchPixel(rainbow, nodes[1]), NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1), tolerance: 0.1) == false)
        assert(similar(branchPixel(rainbow, nodes[1]), NSColor(srgbRed: 124/255, green: 207/255, blue: 141/255, alpha: 1), tolerance: 0.1))
        assert(similar(branchPixel(rainbow, nodes[2]), NSColor(srgbRed: 169/255, green: 166/255, blue: 240/255, alpha: 1), tolerance: 0.1))
        assert(themed.model.setBranchStroke(width: nil, color: "#DE2244FF", style: nil) == false) // No node is selected.
        themed.model.selected = child.id
        assert(themed.model.setBranchStroke(width: nil, color: "#DE2244FF", style: nil))
        themed.needsDisplay = true
        assert(similar(branchPixel(paintTheme(), nodes[1]), NSColor(srgbRed: 222/255, green: 34/255, blue: 68/255, alpha: 1), tolerance: 0.1))
        themed.model.selected = UUID()
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            themed.appearance = NSAppearance(named: appearance)
            let bitmap = paintTheme(), box = nodes[0].frame
            let fill = bitmap.colorAt(x: Int(box.minX + 82), y: bitmap.pixelsHigh - Int(box.minY + 92) - 1)
            assert(similar(fill, .white, tolerance: 0.07), "Rainbow root fill is white even in Dark mode")
            assert(rootTextPixels(bitmap, box).contains { $0.count == 3 && $0.allSatisfy { $0 < 0.55 } },
                   "Root text must contrast against its actual white fill")
        }
        themed.appearance = NSAppearance(named: .darkAqua)
        var blankRoot = themedRoot
        blankRoot.title = ""
        themed.model.roots = [blankRoot]
        themed.needsDisplay = true
        let blankBitmap = paintTheme(), blankBox = mapLayout([blankRoot])[0].frame
        assert(similar(blankBitmap.colorAt(x: Int(blankBox.minX + 82),
                                          y: blankBitmap.pixelsHigh - Int(blankBox.minY + 92) - 1), .white, tolerance: 0.07))
        assert(rootTextPixels(blankBitmap, blankBox).contains { $0.count == 3 && $0.allSatisfy { $0 < 0.4 } },
               "Dark Rainbow blank root placeholder must render dark text inside its white fill")
        themed.model.roots = [themedRoot]
        themed.nativePresentation[root.id] = MindNodePresentation(location: nil, maxWidth: nil,
            allowToShrinkWidth: nil, font: MindNodeFontMetadata(family: nil, pointSize: nil,
                color: [136.0/255, 136.0/255, 136.0/255, 1], alignment: nil, alignmentCode: nil, bold: nil, italic: nil),
            styleChangedByUser: nil, fillColor: nil)
        themed.needsDisplay = true
        assert(rootTextPixels(paintTheme(), nodes[0].frame).contains { $0.count == 3 && $0.allSatisfy { $0 < 0.4 } },
               "Imported #888888 root title must become near-black on white theme fill")
        themed.embeddedTheme = MindNodeThemeMetadata(identifier: nil, backgroundColor: [0.13, 0.27, 0.41, 1],
            allowNodeStrokeColorVariation: nil, baseSubnode: nil, mainNodes: [], subnodeLevels: [])
        assert(similar(paintTheme().colorAt(x: 2, y: 2), NSColor(srgbRed: 0.13, green: 0.27, blue: 0.41, alpha: 1)))
        assert(themed.model.setCanvasColor("#CCBB88FF"))
        themed.needsDisplay = true
        assert(similar(paintTheme().colorAt(x: 2, y: 2), NSColor(srgbRed: 0.8, green: 187/255, blue: 136/255, alpha: 1)))
        themed.nativePresentation[child.id] = MindNodePresentation(location: nil, maxWidth: nil,
            allowToShrinkWidth: nil, font: MindNodeFontMetadata(family: nil, pointSize: nil,
                color: [0.1, 0.1, 0.1, 1], alignment: nil, alignmentCode: nil, bold: nil, italic: nil),
            styleChangedByUser: nil, fillColor: nil)
        func childTextBrightness() -> [CGFloat] {
            let bitmap = paintTheme(), box = nodes[1].frame
            return (Int(box.minX + 96)..<Int(box.maxX + 65)).flatMap { x in
                (Int(box.maxY + 90 - 36)..<Int(box.maxY + 90 - 12)).compactMap { y in
                    rgba(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - y - 1)).first
                }
            }
        }
        assert(childTextBrightness().contains { $0 < 0.25 }, "Legible imported child font stays dark on light canvas")
        themed.nativePresentation[child.id] = MindNodePresentation(location: nil, maxWidth: nil,
            allowToShrinkWidth: nil, font: MindNodeFontMetadata(family: nil, pointSize: nil,
                color: [176.0/255, 176.0/255, 176.0/255, 1], alignment: nil, alignmentCode: nil, bold: nil, italic: nil),
            styleChangedByUser: nil, fillColor: nil)
        assert(themed.model.setCanvasColor("#484848FF"))
        themed.needsDisplay = true
        assert(childTextBrightness().contains { $0 > 0.8 }, "Imported borderline child font must become white on explicit dark canvas")
        print("borderless branch line, native editor, dark/light and AX hit geometry passed")
    }
}
