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
            let exportedBranch = hasInk(exported, theme.branchColors[0], tolerance: 0.055)
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
