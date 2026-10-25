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
        let markdown = exportMarkdown(model.roots, relationships: model.relationships)
        assert(markdown.contains("relationships") && markdown.contains("start") && markdown.contains("end"),
               "Markdown cannot express links; it must disclose their omission")
        print("full-map relationship PNG and Markdown omission disclosure passed")
    }
}
