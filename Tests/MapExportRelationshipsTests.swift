import AppKit
import Darwin

@main enum MapExportRelationshipsTests {
    static func main() throws {
        _ = NSApplication.shared
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var template = (base.path + "/map-export-edges-XXXXXX").utf8CString
        guard let created = template.withUnsafeMutableBufferPointer({ mkdtemp($0.baseAddress) }) else {
            throw POSIXError(.EIO)
        }
        let folder = URL(fileURLWithPath: String(cString: created), isDirectory: true)
        var info = stat()
        guard folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
              folder.deletingLastPathComponent() == base,
              lstat(folder.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Unsafe synthetic folder") }
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = MapNode(id: UUID(), title: "start", children: [], folded: false,
                            location: SIMD2(100, 100))
        let second = MapNode(id: UUID(), title: "end", children: [], folded: false,
                             location: SIMD2(550, 350))
        let model = MapModel(roots: [first, second], selected: UUID())
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let plain = folder.appendingPathComponent("plain.png")
        try exportMap(canvas, as: .png, to: plain)
        let firstBytes = try Data(contentsOf: plain)
        assert(model.setRelationship(MapRelationship(from: first.id, to: second.id,
                                                      control1: SIMD2(180, 170), control2: SIMD2(-170, 200),
                                                      style: .dotted, startArrow: true, endArrow: true)))
        let linked = folder.appendingPathComponent("linked.png")
        try exportMap(canvas, as: .png, to: linked)
        let linkedBytes = try Data(contentsOf: linked)
        assert(firstBytes != linkedBytes, "Detached full-map PNG must render cross-node Bézier, not silently drop it")
        let overrides = Dictionary(uniqueKeysWithValues: model.roots.map {
            ($0.id, MapLayoutOverride(location: nil, maxWidth: nil, allowToShrinkWidth: true,
                                      font: mapFont(isRoot: true, node: $0)))
        })
        let world = Dictionary(uniqueKeysWithValues: mapLayout(model.roots, overrides: overrides).map { ($0.node.id, $0.frame) })
        let curve = relationshipGeometry(model.relationships[0], from: world[first.id]!, to: world[second.id]!)!
        let middle = CGPoint(x: (curve.start.x + 3 * curve.control1.x + 3 * curve.control2.x + curve.end.x) / 8,
                             y: (curve.start.y + 3 * curve.control1.y + 3 * curve.control2.y + curve.end.y) / 8)
        let firstScreen = canvas.frameForAccessibility(first.id)!
        let screen = CGPoint(x: middle.x + firstScreen.minX - world[first.id]!.minX,
                             y: middle.y + firstScreen.minY - world[first.id]!.minY)
        let click = NSEvent.mouseEvent(with: .rightMouseDown,
            location: CGPoint(x: screen.x, y: canvas.bounds.height - screen.y), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        _ = canvas.menu(for: click)
        guard canvas.selectedRelationshipID == model.relationships[0].id else {
            fputs("Export RED selection: screen=\(screen), first=\(firstScreen), world=\(world[first.id]!), middle=\(middle)\n", stderr)
            exit(1)
        }
        let selectedExport = folder.appendingPathComponent("selected.png")
        try exportMap(canvas, as: .png, to: selectedExport)
        let selectedBytes = try Data(contentsOf: selectedExport)
        assert(selectedBytes == linkedBytes,
               "Selected-only control guides and handles must not leak into detached export")
        var colored = model.relationships[0]
        colored.color = "#00EE00FF"
        assert(model.setRelationship(colored))
        let coloredExport = folder.appendingPathComponent("colored.png")
        try exportMap(canvas, as: .png, to: coloredExport)
        let coloredBytes = try Data(contentsOf: coloredExport)
        assert(coloredBytes != linkedBytes,
               "Detached export must paint the configured edge color")
        let markdown = exportMarkdown(model.roots, relationships: model.relationships)
        assert(markdown.contains("relationships") && markdown.contains("start") && markdown.contains("end"),
               "Markdown cannot express links; it must disclose their omission")
        print("full-map relationship PNG and Markdown omission disclosure passed")
    }
}
