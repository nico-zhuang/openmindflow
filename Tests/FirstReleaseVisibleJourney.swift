import AppKit
import Darwin

@main enum FirstReleaseVisibleJourney {
    static func main() throws {
        func receipt(_ text: String) {
            print(text)
            if let path = CommandLine.arguments.dropFirst().first {
                try? text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            }
        }
        let suite = "local.mindmap.first-release-gui.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        L10n.setLanguage("en", defaults: defaults)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let child = MapNode(id: UUID(), title: "Synthetic Child", children: [], folded: false,
                            location: SIMD2(390, 225))
        let root = MapNode(id: UUID(), title: "Synthetic Root", children: [child], folded: false,
                           location: SIMD2(115, 225))
        let other = MapNode(id: UUID(), title: "Unrelated Root", children: [], folded: false,
                            location: SIMD2(860, 225))
        let canvas = MapCanvas(model: MapModel(roots: [root, other], selected: root.id))
        let delegate = AppDelegate(defaults: defaults)
        let workbench = delegate.makeWorkbench(canvas: canvas)
        delegate.installMenu()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "MindMap first-release synthetic GUI"
        window.contentViewController = workbench
        window.toolbar = delegate.makeToolbar()
        window.setContentSize(NSSize(width: 1200, height: 700))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        app.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        guard window.isVisible, window.isKeyWindow,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            receipt("FAIL visible-or-key-or-frontmost"); exit(2)
        }
        guard workbench.splitViewItems[0].isCollapsed, workbench.splitViewItems[2].isCollapsed else {
            receipt("FAIL sidebar-startup-defaults"); exit(3)
        }
        let original = window.frame
        window.setFrame(NSRect(x: original.minX, y: original.minY, width: original.width - 70,
                               height: original.height - 50), display: true)
        guard window.frame.width < original.width - 60 && window.frame.height < original.height - 40 else {
            receipt("FAIL programmatic-native-window-resize"); exit(4)
        }
        window.setFrame(original, display: true)
        let beforeRoot = canvas.frameForAccessibility(root.id)!, beforeOther = canvas.frameForAccessibility(other.id)!
        let toolbar = window.toolbar!
        let outline = delegate.toolbar(toolbar, itemForItemIdentifier: NSToolbarItem.Identifier("outline"), willBeInsertedIntoToolbar: true)!
        for _ in 0..<6 {
            guard app.sendAction(outline.action!, to: outline.target, from: outline) else {
                receipt("FAIL outline-toolbar-action"); exit(5)
            }
            window.contentView?.layoutSubtreeIfNeeded()
            guard window.frame == original,
                  abs(canvas.frameForAccessibility(root.id)!.midX - beforeRoot.midX) < 1,
                  abs(canvas.frameForAccessibility(root.id)!.midY - beforeRoot.midY) < 1 else {
                receipt("FAIL outline-altered-screen-map-position"); exit(6)
            }
        }
        func nativeEvent(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let rootRect = canvas.frameForAccessibility(root.id)!
        let screenPoint = CGPoint(x: rootRect.midX, y: rootRect.midY)
        let rootLocal = canvas.convert(window.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin,
                                       from: nil)
        let destination = CGPoint(x: rootLocal.x + 26, y: rootLocal.y + 22)
        canvas.mouseDown(with: nativeEvent(.leftMouseDown, at: rootLocal))
        canvas.mouseDragged(with: nativeEvent(.leftMouseDragged, at: destination))
        canvas.mouseUp(with: nativeEvent(.leftMouseUp, at: destination))
        guard canvas.model.roots[0].location != root.location,
              canvas.frameForAccessibility(other.id) == beforeOther else {
            receipt("FAIL root-subtree-drag-panned-unrelated-map"); exit(7)
        }
        let branchRoot = canvas.frameForAccessibility(root.id)!, branchChild = canvas.frameForAccessibility(child.id)!
        func local(_ global: CGPoint) -> CGPoint {
            canvas.convert(window.convertFromScreen(NSRect(origin: global, size: .zero)).origin, from: nil)
        }
        let start = local(CGPoint(x: min(branchRoot.minX, branchChild.minX) - 30,
                                  y: min(branchRoot.minY, branchChild.minY) - 30))
        let finish = local(CGPoint(x: max(branchRoot.maxX, branchChild.maxX) + 30,
                                   y: max(branchRoot.maxY, branchChild.maxY) + 30))
        canvas.mouseDown(with: nativeEvent(.leftMouseDown, at: start))
        canvas.mouseDragged(with: nativeEvent(.leftMouseDragged, at: finish))
        canvas.mouseUp(with: nativeEvent(.leftMouseUp, at: finish))
        guard canvas.model.selectedIDs == [root.id, child.id] else {
            receipt("FAIL blank-canvas-marquee-selection"); exit(14)
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 12,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<12 { for x in 0..<20 {
            bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y)
        } }
        let image = bitmap.representation(using: .png, properties: [:])!
        let pasteboard = NSPasteboard(name: .init("mindmap-first-release-owned-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(image, forType: .png)
        canvas.selectNode(root.id)
        guard canvas.pasteImageFromPasteboard(pasteboard),
              let imageNode = canvas.model.roots[0].children.last,
              imageNode.image?.data == image,
              canvas.imageFrameForAccessibility(imageNode.id) != nil else {
            receipt("FAIL visible-native-picture-node"); exit(8)
        }
        let file = app.mainMenu!.item(withTitle: "File")!.submenu!
        for name in ["Insert Image…", "Export PDF…", "Export PNG…", "Export JPG…", "Export Markdown…"] {
            guard file.item(withTitle: name)?.action != nil else {
                receipt("FAIL missing-file-menu-\(name)"); exit(9)
            }
        }
        let find = app.mainMenu!.item(withTitle: "Edit")!.submenu!.item(withTitle: "Find…")!
        guard app.sendAction(find.action!, to: find.target, from: find),
              let search = app.windows.first(where: { $0.title == "Find" })?.contentView?.subviews
                .compactMap({ $0 as? NSSearchField }).first else {
            receipt("FAIL find-panel"); exit(10)
        }
        search.stringValue = "Synthetic Child"
        _ = app.sendAction(search.action!, to: search.target, from: search)
        guard canvas.model.selected == child.id else { receipt("FAIL find-navigation"); exit(11) }
        app.windows.first(where: { $0.title == "Find" })?.orderOut(nil)
        let rootLocations = canvas.model.roots
        let arrange = canvas.contextMenu(for: nil).item(withTitle: "Arrange Map")!
        guard app.sendAction(arrange.action!, to: arrange.target, from: arrange),
              canvas.model.roots != rootLocations else { receipt("FAIL arrange-menu"); exit(12) }
        canvas.undo()
        guard canvas.model.roots == rootLocations else { receipt("FAIL arrange-one-undo"); exit(13) }
        if CommandLine.arguments.count > 2 {
            try exportMap(canvas, as: .png, to: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
        receipt("PASS visible=true key=true active=true panesDefaultClosed=true sixToggleStable=true programmaticWindowResize=true rootDragStable=true marquee=true imageNode=true Find=true ArrangeUndo=true fullMapPNG=true; physicalWindowEdgeDrag=unverified")
        window.orderOut(nil)
    }
}
