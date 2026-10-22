import AppKit

// Runs only inside an isolated, synthetic .app bundle. It never posts desktop-wide input.
@main
enum NativeWindowSelfCheck {
    static func main() {
        guard let path = ProcessInfo.processInfo.environment["MINDMAP_SELFTEST_REPORT"] else {
            fputs("MISSING_OWNED_REPORT\n", stderr); exit(1)
        }
        let report = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let directory = report.deletingLastPathComponent()
        let marker = directory.appendingPathComponent(".owner")
        let attrs = try? FileManager.default.attributesOfItem(atPath: directory.path)
        guard report.lastPathComponent == "report.txt",
              directory.lastPathComponent.hasPrefix("mindmap-native-selfcheck-"),
              (try? String(contentsOf: marker, encoding: .utf8)) == "mindmap-owned-native-selfcheck\n",
              attrs?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
              (attrs?[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              !FileManager.default.fileExists(atPath: report.path) else {
            fputs("UNSAFE_REPORT_DESTINATION\n", stderr); exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let first = MapNode(id: UUID(), title: "Synthetic first", children: [], folded: false)
        let second = MapNode(id: UUID(), title: "Synthetic second", children: [], folded: false)
        let third = MapNode(id: UUID(), title: "Synthetic third", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Synthetic root", children: [first, second, third], folded: false)
        let model = MapModel(roots: [root], selected: root.id)
        let canvas = MapCanvas(model: model)
        let delegate = AppDelegate()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "MindMap Synthetic Self Check"
        window.minSize = NSSize(width: 640, height: 400)
        window.contentViewController = delegate.makeWorkbench(canvas: canvas)
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        var finished = false
        func finish(_ message: String, passed: Bool) {
            guard !finished else { return }
            finished = true
            do {
                guard !FileManager.default.fileExists(atPath: report.path) else { throw CocoaError(.fileWriteFileExists) }
                try (message + "\n").write(to: report, atomically: true, encoding: .utf8)
            } catch {
                fputs("SELFTEST_REPORT_WRITE_FAILED: \(error)\n", stderr)
                window.orderOut(nil)
                exit(1)
            }
            window.orderOut(nil)
            exit(passed ? 0 : 1) // No assert or SIGTRAP: never produce a crash dialog.
        }
        func capture(_ suffix: String) -> Bool {
            let url = report.deletingPathExtension().appendingPathExtension(suffix)
            guard !FileManager.default.fileExists(atPath: url.path),
                  let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return false }
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
            do { try png.write(to: url, options: .atomic); return true }
            catch { return false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { finish("FAIL timeout waiting for own key window", passed: false) }
        var attempts = 0
        func exercise() {
            attempts += 1
            guard window.isVisible && window.isKeyWindow && app.isActive else {
                if attempts < 20 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: exercise) }
                else { finish("FAIL visible=\(window.isVisible) key=\(window.isKeyWindow) active=\(app.isActive)", passed: false) }
                return
            }
            window.contentView?.layoutSubtreeIfNeeded()
            let worldNodes = mapLayout(model.roots)
            let world = worldNodes.reduce(CGRect.null) { $0.union($1.frame) }
            let fit = canvas.fitMapInView()
            guard !fit.isNull, world.width > 0 else {
                finish("FAIL canvas was not laid out bounds=\(canvas.bounds) content=\(String(describing: window.contentView?.bounds))", passed: false)
                return
            }
            let scale = fit.width / world.width
            func point(_ frame: CGRect) -> CGPoint {
                canvas.convert(CGPoint(x: fit.minX + (frame.midX - world.minX) * scale,
                                       y: fit.minY + (frame.midY - world.minY) * scale), to: nil)
            }
            func send(_ type: NSEvent.EventType, _ location: CGPoint, clicks: Int = 1) -> Bool {
                guard let event = NSEvent.mouseEvent(with: type, location: location,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 1, clickCount: clicks, pressure: 1) else { return false }
                window.sendEvent(event) // Scoped to this window, not CGEvent.post.
                return true
            }
            guard let firstFrame = worldNodes.first(where: { $0.node.id == first.id })?.frame,
                  let secondFrame = worldNodes.first(where: { $0.node.id == second.id })?.frame,
                  let thirdFrame = worldNodes.first(where: { $0.node.id == third.id })?.frame else {
                finish("FAIL synthetic nodes absent", passed: false); return
            }
            let firstPoint = point(firstFrame)
            let hit = window.contentView?.hitTest(firstPoint)
            guard hit === canvas else { finish("FAIL child center hit=\(String(describing: type(of: hit)))", passed: false); return }
            guard send(.leftMouseDown, firstPoint), send(.leftMouseUp, firstPoint), model.selected == first.id else {
                finish("FAIL first window click did not select child", passed: false); return
            }
            let secondHit = window.contentView?.hitTest(firstPoint).map { String(describing: type(of: $0)) } ?? "nil"
            var editEvents: [String] = []
            _ = NotificationCenter.default.addObserver(forName: NSControl.textDidBeginEditingNotification, object: nil, queue: nil) { _ in editEvents.append("begin") }
            _ = NotificationCenter.default.addObserver(forName: NSControl.textDidEndEditingNotification, object: nil, queue: nil) { _ in editEvents.append("end") }
            guard send(.leftMouseDown, firstPoint, clicks: 2), send(.leftMouseUp, firstPoint, clicks: 2) else {
                finish("FAIL window double-click NSEvent creation", passed: false); return
            }
            guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first else {
                let focus = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
                let direct = NSEvent.mouseEvent(with: .leftMouseDown, location: firstPoint,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 2, clickCount: 2, pressure: 1)
                if let direct { canvas.mouseDown(with: direct) }
                let directField = canvas.subviews.contains { $0 is NSTextField }
                let afterDirectFocus = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
                finish("FAIL double-click hit=\(secondHit) focus=\(focus) selected=\(model.selected == first.id) events=\(editEvents) directCanvasField=\(directField) directFocus=\(afterDirectFocus)", passed: false)
                return
            }
            let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
            let hasFieldEditor = field.currentEditor() != nil
            field.stringValue = "Synthetic revised"
            canvas.commitEditing()
            let renamed = model.roots[0].children[0].title == "Synthetic revised"
            guard renamed, send(.leftMouseDown, firstPoint, clicks: 2), send(.leftMouseUp, firstPoint, clicks: 2),
                  let reopened = canvas.subviews.compactMap({ $0 as? NSTextField }).first,
                  reopened.currentEditor() != nil, reopened.stringValue == "Synthetic revised" else {
                finish("FAIL submitted title did not reopen for a second native edit", passed: false); return
            }
            guard let input = reopened.currentEditor() as? NSTextView else {
                finish("FAIL inline field editor is not native NSTextView", passed: false); return
            }
            input.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0),
                                replacementRange: NSRange(location: NSNotFound, length: 0))
            guard input.hasMarkedText() else {
                finish("FAIL native inline field rejected marked Chinese composition", passed: false); return
            }
            input.insertText("中文编辑", replacementRange: NSRange(location: NSNotFound, length: 0))
            guard !input.hasMarkedText(), input.string == "中文编辑" else {
                finish("FAIL marked Chinese composition did not commit into inline field", passed: false); return
            }
            let inheritedAppearance = canvas.appearance
            canvas.appearance = NSAppearance(named: .aqua)
            canvas.needsDisplay = true
            let light = capture("light.png")
            canvas.appearance = NSAppearance(named: .darkAqua)
            canvas.needsDisplay = true
            let dark = capture("dark.png")
            canvas.appearance = inheritedAppearance
            canvas.needsDisplay = true
            guard light, dark,
                  let lightData = try? Data(contentsOf: report.deletingPathExtension().appendingPathExtension("light.png")),
                  let darkData = try? Data(contentsOf: report.deletingPathExtension().appendingPathExtension("dark.png")),
                  lightData != darkData else {
                finish("FAIL editor light/dark synthetic images missing or identical", passed: false); return
            }
            canvas.commitEditing()
            guard model.roots[0].children[0].title == "中文编辑" else {
                finish("FAIL native marked text was not saved into model", passed: false); return
            }
            let gapWorld = CGPoint(x: secondFrame.midX,
                                   y: (secondFrame.maxY + thirdFrame.minY) / 2)
            let gap = canvas.convert(CGPoint(x: fit.minX + (gapWorld.x - world.minX) * scale,
                                            y: fit.minY + (gapWorld.y - world.minY) * scale), to: nil)
            guard send(.leftMouseDown, firstPoint), send(.leftMouseDragged, gap) else {
                finish("FAIL synthetic drag event creation", passed: false); return
            }
            guard capture("drag.png") else {
                finish("FAIL synthetic drag snapshot could not be saved safely", passed: false); return
            }
            guard send(.leftMouseUp, gap) else {
                finish("FAIL synthetic drag release creation", passed: false); return
            }
            let order = model.roots[0].children.map(\.id)
            let reordered = order == [second.id, first.id, third.id]
            let undone = canvas.model.undo() && model.roots[0].children.map(\.id) == [first.id, second.id, third.id]
            let secondPoint = point(secondFrame)
            guard send(.leftMouseDown, firstPoint), send(.leftMouseDragged, secondPoint),
                  send(.leftMouseUp, secondPoint) else {
                finish("FAIL synthetic reparent events", passed: false); return
            }
            let reparented = model.roots[0].children.map(\.id) == [second.id, third.id] &&
                model.roots[0].children[0].children.map(\.id) == [first.id]
            let reparentUndo = reparented && canvas.model.undo() &&
                model.roots[0].children.map(\.id) == [first.id, second.id, third.id]
            let beforeInvalid = model.roots
            let invalid = canvas.convert(CGPoint(x: canvas.bounds.maxX - 40,
                                                  y: canvas.bounds.maxY - 40), to: nil)
            guard send(.leftMouseDown, firstPoint), send(.leftMouseDragged, invalid),
                  send(.leftMouseUp, invalid) else {
                finish("FAIL synthetic invalid drop events", passed: false); return
            }
            let invalidPreserved = model.roots == beforeInvalid
            finish("key=true hit=MapCanvas doubleClickEditor=true fieldEditor=\(hasFieldEditor) responder=\(responder) secondEdit=true markedText=true lightDarkImages=true gapReorder=\(reordered) undo=\(undone) reparentUndo=\(reparentUndo) invalidPreserved=\(invalidPreserved)",
                   passed: hasFieldEditor && renamed && reordered && undone && reparentUndo && invalidPreserved)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: exercise)
        app.run()
    }
}
