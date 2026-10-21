import AppKit

@main
enum RenderFixedSample {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        guard !FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
        _ = NSApplication.shared
        func node(_ title: String, _ children: [MapNode] = []) -> MapNode {
            MapNode(id: UUID(), title: title, children: children, folded: false)
        }
        let root = node("2026 项目规划", [
            node("目标与洞察", [node("真实用户任务"), node("中文 English 🧭 长标题要完整显示，而不是被节点边框裁掉")]),
            node("编辑体验", [node("连续输入\n换行标题"), node("拖动 · 折叠 · 撤销")]),
            node("交付验证", [node("打开 → 修改 → 保存 → 重开"), node("失败操作保留当前导图")])
        ])
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 850)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 850,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        canvas.displayIgnoringOpacity(canvas.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]), png.count > 1_000 else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: output, options: .atomic)
        print("Rendered fixed synthetic map (10 nodes): \(output.path)")
    }
}
