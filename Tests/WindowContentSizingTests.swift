import AppKit

@main
enum WindowContentSizingTests {
    static func main() {
        _ = NSApplication.shared // Detached native window, never ordered/key/activated.
        let suiteName = "local.openmindflow.window-content.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = MapNode(id: UUID(), title: "Synthetic root", children: [], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        let delegate = AppDelegate(defaults: defaults)
        let controller = delegate.makeWorkbench(canvas: canvas)
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 1280, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentViewController = controller
        func inspect(_ size: CGSize) {
            window.setContentSize(size)
            window.displayIfNeeded() // redraw the detached window as AppKit does after zoom
            window.contentView?.layoutSubtreeIfNeeded()
            controller.view.layoutSubtreeIfNeeded()
            controller.splitView.layoutSubtreeIfNeeded()
            canvas.layoutSubtreeIfNeeded()
            let content = window.contentView!.bounds
            let split = controller.splitView.bounds
            let actual = canvas.bounds
            guard abs(content.width - size.width) < 1,
                  abs(content.height - size.height) < 1,
                  abs(split.width - content.width) < 1,
                  abs(split.height - content.height) < 1,
                  abs(actual.width - split.width) < 1,
                  abs(actual.height - split.height) < 1 else {
                fputs("Window=\(window.frame) content=\(content) split=\(split) canvas=\(actual) requested=\(size): canvas must fill the resized content\n", stderr)
                exit(1)
            }
        }
        inspect(CGSize(width: 1280, height: 700))
        guard let initialBitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
            fputs("Cannot render initial detached canvas bitmap\n", stderr); exit(1)
        }
        canvas.cacheDisplay(in: canvas.bounds, to: initialBitmap)
        guard let initialCorner = initialBitmap.colorAt(x: 8, y: 8)?.usingColorSpace(.deviceRGB) else {
            fputs("Cannot read initial canvas background\n", stderr); exit(1)
        }
        inspect(CGSize(width: 1800, height: 1050))
        guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
            fputs("Cannot render detached canvas bitmap\n", stderr); exit(1)
        }
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        guard let upperLeft = bitmap.colorAt(x: 8, y: 8)?.usingColorSpace(.deviceRGB),
              let lowerRight = bitmap.colorAt(x: bitmap.pixelsWide - 9, y: bitmap.pixelsHigh - 9)?.usingColorSpace(.deviceRGB),
              abs(upperLeft.redComponent - initialCorner.redComponent) < 0.02,
              abs(upperLeft.greenComponent - initialCorner.greenComponent) < 0.02,
              abs(upperLeft.blueComponent - initialCorner.blueComponent) < 0.02,
              abs(lowerRight.redComponent - initialCorner.redComponent) < 0.02,
              abs(lowerRight.greenComponent - initialCorner.greenComponent) < 0.02,
              abs(lowerRight.blueComponent - initialCorner.blueComponent) < 0.02 else {
            fputs("Resized canvas must paint the same background color into opposite corners\n", stderr); exit(1)
        }
        inspect(CGSize(width: 980, height: 600))
        print("detached window content and canvas remain edge-to-edge on resize")
    }
}
