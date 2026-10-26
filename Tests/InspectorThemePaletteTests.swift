import AppKit
import Darwin

@main
enum InspectorThemePaletteTests {
    static func main() {
        let ids = ["tropical", "rainbow", "candyland", "vintage", "greyscale", "teal", "slate",
                   "blackberry", "blackboard", "coffee", "swing"]
        assert(InspectorTheme.allCases.map(\.rawValue) == ids, "Eleven stable theme IDs must be selectable")
        let legacy: [(InspectorTheme, String, [String])] = [
            (.tropical, "#FFFFFFFF", ["#52C6C4FF", "#FF9955FF", "#F6CC49FF", "#A94ECCFF"]),
            (.rainbow, "#FFFFFFFF", ["#7CCF8DFF", "#A9A6F0FF", "#FF9A60FF", "#46C3C9FF"]),
            (.candyland, "#EF1760FF", ["#A1D56FFF", "#F248A8FF", "#3EB9B6FF", "#C95A6AFF"])
        ]
        for (theme, fill, colors) in legacy {
            assert(theme.rootFill == fill && theme.branchColors == colors, "Existing theme result changed")
            assert(theme.canvasBackground == nil, "Existing themes retain native background")
        }
        for theme in InspectorTheme.allCases {
            assert(MapNode.validColor(theme.rootFill) && theme.branchColors.count >= 3)
            assert(theme.branchColors.allSatisfy(MapNode.validColor))
            assert(theme.canvasBackground.map(MapNode.validColor) ?? true)
            assert(theme.rootTitleColor.map(MapNode.validColor) ?? true)
            assert(theme.branchTitleColor.map(MapNode.validColor) ?? true)
        }
        assert(Set(InspectorTheme.allCases.compactMap(\.canvasBackground)).count == 8)

        // Independent category checks from the eleven-theme reference screenshot: these do not
        // compare palette values to themselves or require pixel-perfect screenshot matching.
        func channels(_ hex: String) -> (Double, Double, Double) {
            let value = UInt32(hex.dropFirst(), radix: 16)!
            return (Double((value >> 24) & 255) / 255,
                    Double((value >> 16) & 255) / 255,
                    Double((value >> 8) & 255) / 255)
        }
        func luminance(_ hex: String) -> Double {
            let (r, g, b) = channels(hex)
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        func saturation(_ hex: String) -> Double {
            let (r, g, b) = channels(hex)
            let high = max(r, g, b)
            return high == 0 ? 0 : (high - min(r, g, b)) / high
        }
        func hueBucket(_ hex: String) -> Int {
            let (r, g, b) = channels(hex)
            let high = max(r, g, b), low = min(r, g, b), delta = high - low
            guard delta > 0 else { return -1 }
            let sector: Double
            if high == r { sector = (g - b) / delta }
            else if high == g { sector = (b - r) / delta + 2 }
            else { sector = (r - g) / delta + 4 }
            return Int(floor((sector + 6).truncatingRemainder(dividingBy: 6)))
        }
        func contrast(_ a: String, _ b: String) -> Double {
            let x = luminance(a), y = luminance(b)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        let visualRanges: [(InspectorTheme, ClosedRange<Double>, ClosedRange<Double>)] = [
            (.vintage, 0.88...1, 0.045...0.17),    // near-white / chocolate
            (.greyscale, 0.80...0.95, 0.84...1), // light neutral / near-white
            (.teal, 0.76...0.92, 0.86...1),     // pale cyan / white
            (.slate, 0.055...0.16, 0.86...1),   // blue-gray / white
            (.blackberry, 0.01...0.065, 0...0.035), // wine / near-black
            (.blackboard, 0.01...0.065, 0...0.035), // forest / near-black
            (.coffee, 0...0.035, 0...0.018),   // charcoal / black
            (.swing, 0...0.035, 0.025...0.11) // black-purple / muted violet
        ]
        for (theme, backdropRange, rootRange) in visualRanges {
            let backdrop = theme.canvasBackground!
            assert(backdropRange.contains(luminance(backdrop)), "\(theme) screenshot background light/dark category")
            assert(rootRange.contains(luminance(theme.rootFill)), "\(theme) screenshot root light/dark category")
            assert(contrast(theme.rootTitleColor!, theme.rootFill) >= 4.5,
                   "\(theme) root title candidate must contrast with root fill")
            assert(contrast(theme.branchTitleColor!, backdrop) >= 4.5,
                   "\(theme) branch title candidate must contrast with canvas")
        }
        let (tealR, tealG, tealB) = channels(InspectorTheme.teal.canvasBackground!)
        assert(tealG > tealR + 0.035 && tealB > tealR + 0.035, "Teal canvas must be cyan, not neutral")
        let (slateR, slateG, slateB) = channels(InspectorTheme.slate.canvasBackground!)
        assert(slateB > slateR && slateG > slateR, "Slate canvas must be blue-gray")
        let (berryR, _, berryB) = channels(InspectorTheme.blackberry.canvasBackground!)
        assert(berryR > berryB * 0.85, "Blackberry canvas must be wine-plum")
        let (boardR, boardG, _) = channels(InspectorTheme.blackboard.canvasBackground!)
        assert(boardG > boardR * 1.3, "Blackboard canvas must be forest green")
        for color in InspectorTheme.greyscale.branchColors {
            assert(saturation(color) <= 0.055 && luminance(color) < 0.48,
                   "Greyscale branches must be dark neutral strokes")
        }
        for theme in [InspectorTheme.vintage, .teal, .slate, .blackberry, .blackboard, .coffee, .swing] {
            let colors = theme.branchColors
            assert(colors.count >= 6, "\(theme) screenshot shows six varied branch strokes")
            let minSaturation = theme == .blackboard ? 0.30 : 0.45
            assert(colors.filter { saturation($0) >= minSaturation }.count >= 5,
                   "\(theme) branches must retain distinct colorful strokes")
            assert(Set(colors.map(hueBucket)).count >= 4, "\(theme) branches must span several hue families")
        }
        assert(InspectorTheme.coffee.branchColors.filter { saturation($0) >= 0.70 }.count >= 5,
               "Coffee branches must look fluorescent against charcoal")
        let tealBuckets = Set(InspectorTheme.teal.branchColors.map(hueBucket))
        assert([0, 2, 3, 4, 5].filter(tealBuckets.contains).count >= 4,
               "Teal needs warm reds/oranges plus cool teals/purples")

        let root = MapNode(id: UUID(), title: "Root", children: [], folded: false)
        let model = MapModel(roots: [root], selected: root.id)
        for id in ids {
            assert(model.setTheme(id), "Selecting \(id) should be a real undoable model change")
            assert(model.theme == id)
            assert(model.undo() && model.theme == nil)
            assert(model.redo() && model.theme == id)
            assert(model.setTheme(nil))
        }
        let invalid = MapModel(roots: [root], selected: root.id)
        assert(!invalid.setTheme("invalid") && invalid.theme == nil)
        assert(!invalid.undo(), "Invalid ID must not create history")
        _ = NSApplication.shared // Offscreen graphics only; no window or focus changes.
        func rgb(_ hex: String) -> NSColor {
            let bytes = UInt32(hex.dropFirst(), radix: 16)!
            return NSColor(srgbRed: CGFloat((bytes >> 24) & 255) / 255,
                green: CGFloat((bytes >> 16) & 255) / 255,
                blue: CGFloat((bytes >> 8) & 255) / 255, alpha: CGFloat(bytes & 255) / 255)
        }
        func matches(_ color: NSColor?, _ hex: String, tolerance: CGFloat = 0.035) -> Bool {
            guard let pixel = color?.usingColorSpace(.deviceRGB),
                  let target = rgb(hex).usingColorSpace(.deviceRGB) else { return false }
            return abs(pixel.redComponent - target.redComponent) < tolerance &&
                abs(pixel.greenComponent - target.greenComponent) < tolerance &&
                abs(pixel.blueComponent - target.blueComponent) < tolerance
        }
        var rootWithBranch = root
        rootWithBranch.children = [MapNode(id: UUID(), title: "Branch", children: [], folded: false)]
        let canvasModel = MapModel(roots: [rootWithBranch], selected: UUID())
        let canvas = MapCanvas(model: canvasModel)
        canvas.appearance = NSAppearance(named: .aqua)
        canvas.frame = CGRect(x: 0, y: 0, width: 520, height: 310)
        func screen() -> NSBitmapImageRep {
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 520, pixelsHigh: 310,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
            canvas.effectiveAppearance.performAsCurrentDrawingAppearance { canvas.draw(canvas.bounds) }
            NSGraphicsContext.current = previous
            return image
        }
        func hasInk(_ image: NSBitmapImageRep, _ hex: String, tolerance: CGFloat = 0.035) -> Bool {
            stride(from: 0, to: image.pixelsWide, by: 2).contains { x in
                stride(from: 0, to: image.pixelsHigh, by: 2).contains { y in
                    matches(image.colorAt(x: x, y: y), hex, tolerance: tolerance)
                }
            }
        }
        var pattern = (FileManager.default.temporaryDirectory.path + "/theme-palette-XXXXXX").utf8CString
        let scratch = pattern.withUnsafeMutableBufferPointer { bytes -> URL in
            guard let start = bytes.baseAddress, let path = mkdtemp(start) else { fatalError("Cannot create test directory") }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var info = stat()
        guard scratch.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent() == base,
              lstat(scratch.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { fatalError("Unsafe test directory") }
        defer { try? FileManager.default.removeItem(at: scratch) }
        for theme in InspectorTheme.allCases {
            assert(canvasModel.setTheme(theme.rawValue))
            let painted = screen()
            if let backdrop = theme.canvasBackground {
                assert(matches(painted.colorAt(x: 0, y: 0), backdrop), "\(theme) screen background")
            }
            assert(hasInk(painted, theme.rootFill), "\(theme) root fill missing from pixels")
            assert(hasInk(painted, theme.branchColors[0]), "\(theme) branch ink missing from pixels")
            let output = scratch.appendingPathComponent("\(theme.rawValue).png")
            try! exportMap(canvas, as: .png, to: output)
            let exported = NSBitmapImageRep(data: try! Data(contentsOf: output))!
            if let backdrop = theme.canvasBackground {
                let corner = exported.colorAt(x: 0, y: 0)
                assert(matches(corner, backdrop, tolerance: 0.13), "\(theme) detached PNG background \(String(describing: corner)) expected \(backdrop)")
            }
            let exportedFill = hasInk(exported, theme.rootFill, tolerance: 0.13)
            let exportedBranch = hasInk(exported, theme.branchColors[0], tolerance: 0.13) // PNG profile conversion shifts saturated RGB channels.
            assert(exportedFill && exportedBranch,
                   "\(theme) exported fill=\(exportedFill) branch=\(exportedBranch) diverges")
        }
        canvasModel.selected = rootWithBranch.children[0].id
        assert(canvasModel.setBranchStroke(color: "#123456FF"))
        assert(canvasModel.setTheme("blackboard"))
        canvas.needsDisplay = true // The real inspector invalidates canvas after model changes.
        assert(hasInk(screen(), "#123456FF"), "Explicit node stroke overrides theme")
        assert(canvasModel.setCanvasColor("#AABBCCFF"))
        assert(matches(screen().colorAt(x: 0, y: 0), "#AABBCCFF"), "Explicit canvas overrides theme")
        assert(canvasModel.setTheme(nil))
        assert(matches(screen().colorAt(x: 0, y: 0), "#AABBCCFF"), "Unset theme retains explicit canvas")
        assert(canvasModel.setCanvasColor(nil))
        canvas.embeddedTheme = MindNodeThemeMetadata(identifier: nil,
            backgroundColor: [0.2, 0.3, 0.4, 1], allowNodeStrokeColorVariation: nil,
            baseSubnode: nil, mainNodes: [], subnodeLevels: [])
        assert(matches(screen().colorAt(x: 0, y: 0), "#334D66FF"), "Imported background survives without a theme")
        assert(canvasModel.setTheme("vintage"))
        assert(matches(screen().colorAt(x: 0, y: 0), InspectorTheme.vintage.canvasBackground!),
               "Chosen theme backdrop supersedes imported fallback")
        canvasModel.selected = root.id
        assert(canvasModel.setRootFillColor("#103254FF"))
        canvas.needsDisplay = true
        assert(hasInk(screen(), "#103254FF"), "Explicit root fill overrides theme")
        print("theme IDs, palettes, screen/PNG pixels, overrides and Undo/Redo passed")
    }
}
