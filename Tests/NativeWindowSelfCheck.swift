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
            let source = MapNode(id: UUID(), title: "Move into gap", children: [], folded: false)
            let before = MapNode(id: UUID(), title: "Before", children: [], folded: false)
            let after = MapNode(id: UUID(), title: "After", children: [], folded: false)
            let destination = MapNode(id: UUID(), title: "Destination", children: [before, after], folded: false)
            let crossModel = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [source, destination], folded: false)],
                                      selected: source.id)
            canvas.model = crossModel
            let crossNodes = mapLayout(crossModel.roots)
            let crossWorld = crossNodes.reduce(CGRect.null) { $0.union($1.frame) }
            let crossFit = canvas.fitMapInView()
            let crossScale = crossFit.width / crossWorld.width
            func crossPoint(_ location: CGPoint) -> CGPoint {
                canvas.convert(CGPoint(x: crossFit.minX + (location.x - crossWorld.minX) * crossScale,
                                       y: crossFit.minY + (location.y - crossWorld.minY) * crossScale), to: nil)
            }
            let sourceBox = crossNodes.first { $0.node.id == source.id }!.frame
            let beforeBox = crossNodes.first { $0.node.id == before.id }!.frame
            let afterBox = crossNodes.first { $0.node.id == after.id }!.frame
            let crossStart = crossPoint(CGPoint(x: sourceBox.midX, y: sourceBox.midY))
            let crossGap = crossPoint(CGPoint(x: beforeBox.midX, y: (beforeBox.maxY + afterBox.minY) / 2))
            guard send(.leftMouseDown, crossStart), send(.leftMouseDragged, crossGap),
                  send(.leftMouseUp, crossGap),
                  crossModel.roots[0].children.last?.children.map(\.id) == [before.id, source.id, after.id],
                  crossModel.undo(), crossModel.roots[0].children.map(\.id) == [source.id, destination.id] else {
                finish("FAIL native cross-branch child-gap drop or undo", passed: false); return
            }
            for round in 2...3 {
                window.contentView?.layoutSubtreeIfNeeded()
                let nodes = (canvas.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
                guard let sourceAX = nodes.first(where: { $0.accessibilityLabel() == source.title }),
                      let beforeAX = nodes.first(where: { $0.accessibilityLabel() == before.title }),
                      let afterAX = nodes.first(where: { $0.accessibilityLabel() == after.title }) else {
                    finish("FAIL native cross-branch round \(round) coordinates unavailable", passed: false); return
                }
                let start = window.convertFromScreen(sourceAX.accessibilityFrame())
                let upper = window.convertFromScreen(beforeAX.accessibilityFrame())
                let lower = window.convertFromScreen(afterAX.accessibilityFrame())
                let from = CGPoint(x: start.midX, y: start.midY)
                let gap = CGPoint(x: upper.midX, y: (upper.minY + lower.maxY) / 2)
                guard window.contentView?.hitTest(from) === canvas, window.contentView?.hitTest(gap) === canvas,
                      send(.leftMouseDown, from), send(.leftMouseDragged, gap), send(.leftMouseUp, gap),
                      crossModel.roots[0].children.map(\.id) == [destination.id],
                      crossModel.roots[0].children[0].children.map(\.id) == [before.id, source.id, after.id],
                      crossModel.undo(), crossModel.roots[0].children == [source, destination] else {
                    finish("FAIL native cross-branch round \(round) drag or undo", passed: false); return
                }
            }
            let deep = MapNode(id: UUID(), title: "Deep", children: [], folded: false)
            let nested = MapNode(id: UUID(), title: "Nested", children: [
                MapNode(id: UUID(), title: "Inner", children: [deep], folded: false)
            ], folded: false)
            let folded = MapNode(id: UUID(), title: "Folded", children: [
                MapNode(id: UUID(), title: "Hidden", children: [], folded: false)
            ], folded: true)
            let leaf = MapNode(id: UUID(), title: "Leaf", children: [], folded: false)
            canvas.model = MapModel(roots: [MapNode(id: UUID(), title: "Root", children: [nested, folded, leaf], folded: false)], selected: deep.id)
            window.setContentSize(NSSize(width: 1000, height: 700))
            window.contentView?.layoutSubtreeIfNeeded()
            canvas.selectAndEdit(deep.id)
            guard let deepField = canvas.subviews.compactMap({ $0 as? NSTextField }).first else {
                finish("FAIL deep inline editor missing", passed: false); return
            }
            let wideWidth = canvas.bounds.width
            deepField.stringValue = "Edited while narrowing"
            window.setContentSize(NSSize(width: 640, height: 400))
            window.contentView?.layoutSubtreeIfNeeded()
            guard canvas.bounds.width < wideWidth, window.isKeyWindow,
                  canvas.bounds.insetBy(dx: 28, dy: 28).contains(deepField.frame),
                  deepField.currentEditor() != nil else {
                finish("FAIL native narrow editor frame=\(deepField.frame) canvas=\(canvas.bounds) key=\(window.isKeyWindow)", passed: false); return
            }
            func axHelp(_ title: String) -> String? {
                (canvas.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
                    .first { $0.accessibilityLabel() == title }?.accessibilityHelp()
            }
            guard axHelp("Folded") == "Collapsed, 1 child", axHelp("Leaf") == nil else {
                finish("FAIL native canvas folded AX help=\(axHelp("Folded") ?? "nil") leaf=\(axHelp("Leaf") ?? "nil")", passed: false); return
            }
            canvas.selectNode(folded.id) // Commits the active editor before folding another node.
            canvas.toggleFold()
            guard canvas.model.roots[0].children[0].children[0].children[0].title == "Edited while narrowing",
                  axHelp("Folded") == "Expanded, 1 child", window.isKeyWindow else {
                finish("FAIL native canvas expanded AX help=\(axHelp("Folded") ?? "nil") or lost inline edit/key window", passed: false); return
            }
            let longNode = MapNode(id: UUID(), title: String(repeating: "Long editable idea ", count: 80),
                                   children: [], folded: false)
            canvas.model = MapModel(roots: [longNode], selected: longNode.id)
            canvas.selectAndEdit(longNode.id)
            guard let longField = canvas.subviews.compactMap({ $0 as? NSTextField }).first,
                  longField.currentEditor() != nil,
                  canvas.bounds.insetBy(dx: 28, dy: 28).contains(longField.frame),
                  window.isKeyWindow else {
                finish("FAIL native long-title editor outside narrow viewport or lost focus", passed: false); return
            }
            let endKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: "\u{f701}", charactersIgnoringModifiers: "\u{f701}",
                                         isARepeat: false, keyCode: 125)!
            window.sendEvent(endKey) // Local key event to this synthetic window only.
            guard let fieldEditor = longField.currentEditor() as? NSTextView else {
                finish("FAIL native multiline field editor is not NSTextView", passed: false); return
            }
            let end = (longField.stringValue as NSString).length
            let caret = fieldEditor.firstRect(forCharacterRange: NSRange(location: end, length: 0), actualRange: nil)
            let fieldOnScreen = window.convertToScreen(canvas.convert(longField.frame, to: nil))
            guard fieldEditor.selectedRange.location == end,
                  fieldOnScreen.contains(caret.origin) else {
                finish("FAIL long-title caret did not scroll into visible native editor", passed: false); return
            }
            let typeEnd = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          characters: "x", charactersIgnoringModifiers: "x",
                                          isARepeat: false, keyCode: 7)!
            window.sendEvent(typeEnd) // Only this owned window's active native field editor.
            canvas.commitEditing()
            guard canvas.model.roots[0].title == longNode.title + "x" else {
                finish("FAIL native long-title keyboard insertion or commit truncated text", passed: false); return
            }
            let thirtyChildren = (0..<29).map { index in
                MapNode(id: UUID(), title: index == 28 ? String(repeating: "Distant idea ", count: 30) : "Idea \(index)",
                        children: [], folded: false)
            }
            let distant = thirtyChildren[28]
            let thirtyRoot = MapNode(id: UUID(), title: "Root", children: thirtyChildren, folded: false)
            canvas.model = MapModel(roots: [thirtyRoot], selected: thirtyRoot.id)
            window.setContentSize(NSSize(width: 640, height: 400))
            window.contentView?.layoutSubtreeIfNeeded()
            canvas.selectAndEdit(distant.id)
            guard let distantField = canvas.subviews.compactMap({ $0 as? NSTextField }).first,
                  canvas.model.selected == distant.id,
                  canvas.bounds.insetBy(dx: 28, dy: 28).contains(distantField.frame),
                  distantField.currentEditor() != nil, window.isKeyWindow else {
                finish("FAIL native 30-node distant editor outside narrow canvas or lost focus", passed: false); return
            }
            window.sendEvent(endKey)
            window.sendEvent(typeEnd)
            guard distantField.currentEditor() != nil, window.isKeyWindow else {
                finish("FAIL native 30-node editor lost key focus while typing", passed: false); return
            }
            canvas.commitEditing()
            guard canvas.model.roots[0].children[28].title == distant.title + "x",
                  mapLayout(canvas.model.roots).count == 30 else {
                finish("FAIL native 30-node distant title typing, commit, or count", passed: false); return
            }
            finish("key=true hit=MapCanvas doubleClickEditor=true fieldEditor=\(hasFieldEditor) responder=\(responder) secondEdit=true markedText=true lightDarkImages=true gapReorder=\(reordered) undo=\(undone) reparentUndo=\(reparentUndo) invalidPreserved=\(invalidPreserved) crossBranchGap=true threeRoundDrag=true narrowEditor=true foldAX=true longTitle=true thirtyNodeFocus=true",
                   passed: hasFieldEditor && renamed && reordered && undone && reparentUndo && invalidPreserved)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: exercise)
        app.run()
    }
}
