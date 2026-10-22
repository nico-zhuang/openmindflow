import AppKit

// An isolated, marked app fixture only; never choose a path outside its 0700 directory.
@main
enum NativePanelSelfCheck {
    static func main() {
        guard let path = ProcessInfo.processInfo.environment["MINDMAP_SELFTEST_REPORT"] else { exit(1) }
        let report = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let directory = report.deletingLastPathComponent()
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        guard report.lastPathComponent == "report.txt",
              directory.lastPathComponent.hasPrefix("mindmap-native-panel-"),
              (try? String(contentsOf: directory.appendingPathComponent(".owner"), encoding: .utf8)) == "mindmap-owned-native-panel\n",
              attributes?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
              (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              !FileManager.default.fileExists(atPath: report.path) else { exit(1) }
        let expected = directory.appendingPathComponent("Untitled.mindmap.json")
        let ready = directory.appendingPathComponent("panel-ready")
        guard !FileManager.default.fileExists(atPath: expected.path),
              !FileManager.default.fileExists(atPath: ready.path) else { exit(1) }
        let opening = ProcessInfo.processInfo.environment["MINDMAP_PANEL_ACTION"] == "open-cancel"
        let failing = ProcessInfo.processInfo.environment["MINDMAP_PANEL_ACTION"] == "save-failure"
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let document = AppDelegate()
        app.delegate = document
        var ended = false
        func finish(_ result: String, ok: Bool) {
            guard !ended else { return }
            ended = true
            do { try (result + "\n").write(to: report, atomically: true, encoding: .utf8) }
            catch { fputs("REPORT_WRITE_FAILED\n", stderr); exit(1) }
            exit(ok ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { finish("FAIL native panel timeout", ok: false) }
        var focusChecks = 0
        func exercise() {
            guard app.isActive, let window = app.keyWindow, let content = window.contentView else {
                focusChecks += 1
                if [1, 12].contains(focusChecks), NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.deepseek.dsh" {
                    app.windows.first?.makeKeyAndOrderFront(nil)
                    app.activate(ignoringOtherApps: true)
                }
                if focusChecks < 30 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: exercise) }
                else { finish("FAIL own app not key active=\(app.isActive) key=\(app.keyWindow != nil) visible=\(app.windows.filter(\.isVisible).count) frontOwn=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid())", ok: false) }
                return
            }
            var views = [content]
            var canvas: MapCanvas?
            while let view = views.popLast() {
                if let found = view as? MapCanvas { canvas = found; break }
                views += view.subviews
            }
            guard let canvas else { finish("FAIL native canvas missing", ok: false); return }
            if ProcessInfo.processInfo.environment["MINDMAP_PANEL_ACTION"] == "outline-return" {
                var queue = [content]
                var outline: NSOutlineView?
                while let view = queue.popLast() {
                    if let found = view as? NSOutlineView { outline = found; break }
                    queue += view.subviews
                }
                guard let outline, app.mainMenu?.item(withTitle: "Node")?.submenu?
                    .item(withTitle: "New Sibling")?.keyEquivalent == "\r" else {
                    finish("FAIL real outline or Return menu missing", ok: false); return
                }
                canvas.addChild()
                guard let child = canvas.model.roots.first?.children.first?.id,
                      let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first else {
                    finish("FAIL synthetic child setup", ok: false); return
                }
                field.stringValue = "Synthetic child"
                canvas.commitEditing()
                outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
                guard outline.selectedRow == 1, canvas.model.selected == child,
                      window.makeFirstResponder(outline), window.isKeyWindow else {
                    finish("FAIL outline child keyboard focus setup", ok: false); return
                }
                let title = window.title
                guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                    isARepeat: false, keyCode: 36) else {
                    finish("FAIL local Return event creation", ok: false); return
                }
                app.postEvent(event, atStart: false) // Own application queue; menu sees the key equivalent.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    let editor = canvas.subviews.compactMap { $0 as? NSTextField }.first
                    guard window.isKeyWindow, canvas.model.selected == child,
                          canvas.model.roots[0].children.count == 1, window.title == title,
                          editor?.stringValue == "Synthetic child", editor?.currentEditor() != nil else {
                        finish("FAIL outline Return selectedSame=\(canvas.model.selected == child) siblings=\(canvas.model.roots[0].children.count) field=\(editor != nil)", ok: false)
                        return
                    }
                    finish("nativeOutlineReturn=true sameNode=true noSibling=true key=true", ok: true)
                }
                return
            }
            canvas.selectAndEdit(canvas.model.selected)
            guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first else {
                finish("FAIL native inline editor missing", ok: false); return
            }
            guard let selectAll = app.mainMenu?.item(withTitle: "Edit")?.submenu?.item(withTitle: "Select All"),
                  let action = selectAll.action, let editor = field.currentEditor() else {
                finish("FAIL native Select All menu or field editor missing", ok: false); return
            }
            editor.selectedRange = NSRange(location: 0, length: 0)
            guard app.sendAction(action, to: selectAll.target, from: selectAll),
                  editor.selectedRange.length == (editor.string as NSString).length else {
                finish("FAIL native Select All responder-chain action", ok: false); return
            }
            field.stringValue = "Synthetic saved root"
            canvas.commitEditing()
            guard canvas.model.roots[0].title == "Synthetic saved root", window.title.contains(" •") else {
                finish("FAIL editable root did not become dirty", ok: false); return
            }
            var attempts = 0
            var result = "FAIL native \(opening ? "Open" : "Save") panel missing"
            var validated = false
            let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
                attempts += 1
                if let panel = app.modalWindow as? NSSavePanel {
                    let directoryOwned = panel.directoryURL?.resolvingSymlinksInPath() == directory
                    let selectedOwned = opening || panel.url?.resolvingSymlinksInPath() == expected
                    if !validated {
                        result = "FAIL \(opening ? "Open" : "Save") panel dirOwned=\(directoryOwned) urlOwned=\(selectedOwned)"
                        if directoryOwned && selectedOwned && (!opening || panel is NSOpenPanel) {
                            do { try "ready\n".write(to: ready, atomically: true, encoding: .utf8) }
                            catch { timer.invalidate(); panel.cancel(nil); return }
                            validated = true
                            result = opening ? "nativeOpenPanel=true" : "nativeSavePanel=true"
                        }
                    }
                }
                if attempts >= 100 {
                    result = "FAIL native \(opening ? "Open" : "Save") panel timeout"
                    timer.invalidate()
                    if let panel = app.modalWindow as? NSSavePanel { panel.cancel(nil) }
                    else { app.abortModal() }
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            let openItem = app.mainMenu?.item(withTitle: "File")?.submenu?.item(withTitle: "Open Own JSON…")
            let actionDispatched: Bool
            if opening, let openItem, let action = openItem.action {
                actionDispatched = app.sendAction(action, to: openItem.target, from: openItem)
            } else {
                actionDispatched = !opening && app.sendAction(NSSelectorFromString("saveFile:"), to: document, from: nil)
            }
            timer.invalidate()
            let savedExists = FileManager.default.fileExists(atPath: expected.path)
            if opening {
                guard actionDispatched, result == "nativeOpenPanel=true", !savedExists,
                      canvas.model.roots[0].title == "Synthetic saved root",
                      window.title == "Untitled • — MindMap" else {
                    finish("FAIL cancelled Open \(result) retained=\(!savedExists) dirty=\(window.title == "Untitled • — MindMap")", ok: false)
                    return
                }
                finish("nativeOpenCancel=true ownModelRetained=true dirtyRetained=true nativeSelectAll=true", ok: true)
                return
            }
            if failing {
                guard actionDispatched, result == "nativeSavePanel=true", !savedExists,
                      canvas.model.roots[0].title == "Synthetic saved root",
                      window.title == "Untitled • — MindMap" else {
                    finish("FAIL Save failure unexpectedlySaved=\(savedExists) dirtyRetained=\(window.title == "Untitled • — MindMap")", ok: false)
                    return
                }
                finish("nativeSaveFailure=true ownModelRetained=true dirtyRetained=true ownJSONAbsent=true", ok: true)
                return
            }
            if ProcessInfo.processInfo.environment["MINDMAP_PANEL_ACTION"] == "cancel" {
                guard actionDispatched, result == "nativeSavePanel=true", !savedExists,
                      canvas.model.roots[0].title == "Synthetic saved root",
                      window.title == "Untitled • — MindMap" else {
                    finish("FAIL cancelled Save retained=\(!savedExists) dirty=\(window.title == "Untitled • — MindMap")", ok: false)
                    return
                }
                finish("nativeSaveCancel=true ownModelRetained=true dirtyRetained=true nativeSelectAll=true", ok: true)
                return
            }
            guard actionDispatched, result == "nativeSavePanel=true", let roots = try? readOwnJSON(expected),
                  roots.count == 1, roots[0].title == "Synthetic saved root",
                  window.title == "Untitled.mindmap.json — MindMap" else {
                finish("FAIL \(result) actionDispatched=\(actionDispatched) savedExists=\(savedExists) titleClean=\(window.title == "Untitled.mindmap.json — MindMap") attempts=\(attempts)", ok: false)
                return
            }
            finish("nativeSavePanel=true ownJSONDecoded=true nativeOpenPanel=unverified nativeSelectAll=true", ok: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: exercise)
        app.run()
    }
}
