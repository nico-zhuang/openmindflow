import AppKit
import Darwin

@main enum NativeImportVisibleJourney {
    static func main() {
        func receipt(_ message: String) {
            print(message)
            if let path = CommandLine.arguments.dropFirst().first {
                try? message.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let child = MapNode(id: UUID(), title: "Synthetic branch", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Synthetic root", children: [child], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        let font = MindNodeFontMetadata(family: "STSongti-SC-Regular", pointSize: 36,
            color: [1, 1, 1, 1], alignment: "center", alignmentCode: nil, bold: nil, italic: nil)
        canvas.nativePresentation = [root.id: MindNodePresentation(location: CGPoint(x: 200, y: 120),
            maxWidth: 300, allowToShrinkWidth: true, font: font, styleChangedByUser: false,
            fillColor: [0.32, 0.18, 0.55, 1]), child.id: MindNodePresentation(
            location: CGPoint(x: 470, y: 160), maxWidth: 136,
            allowToShrinkWidth: false, font: nil, styleChangedByUser: false, fillColor: nil)]
        let window = NSWindow(contentRect: CGRect(x: 120, y: 100, width: 780, height: 460),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "MindMap native import synthetic acceptance"
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
        guard window.isVisible && window.isKeyWindow && front else {
            receipt("FAIL visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) active=\(front) appActive=\(app.isActive) appKey=\(app.keyWindow?.title ?? "none") appMain=\(app.mainWindow?.title ?? "none") appWindowCount=\(app.windows.count)")
            exit(1)
        }
        guard let hit = canvas.frameForAccessibility(child.id), hit.width == 136,
              canvas.accessibilityChildren()?.count ?? 0 >= 2 else { receipt("FAIL imported-geometry-or-AX"); exit(2) }
        canvas.selectAndEdit(root.id)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first,
              field.font?.pointSize == 36, field.currentEditor() != nil else { receipt("FAIL original-font-or-real-editor-focus"); exit(3) }
        receipt("PASS visible=true key=true active=true imported-geometry=true editor=true")
        window.orderOut(nil)
    }
}
