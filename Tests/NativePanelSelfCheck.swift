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
            canvas.selectAndEdit(canvas.model.selected)
            guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first else {
                finish("FAIL native inline editor missing", ok: false); return
            }
            field.stringValue = "Synthetic saved root"
            canvas.commitEditing()
            guard canvas.model.roots[0].title == "Synthetic saved root", window.title.contains(" •") else {
                finish("FAIL editable root did not become dirty", ok: false); return
            }
            var attempts = 0
            var result = "FAIL native Save panel missing"
            var validated = false
            let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
                attempts += 1
                if let panel = app.modalWindow as? NSSavePanel {
                    let directoryOwned = panel.directoryURL?.resolvingSymlinksInPath() == directory
                    let selectedOwned = panel.url?.resolvingSymlinksInPath() == expected
                    if !validated {
                        result = "FAIL Save panel dirOwned=\(directoryOwned) urlOwned=\(selectedOwned)"
                        if directoryOwned && selectedOwned {
                            do { try "ready\n".write(to: ready, atomically: true, encoding: .utf8) }
                            catch { timer.invalidate(); panel.cancel(nil); return }
                            validated = true
                            result = "nativeSavePanel=true"
                        }
                    }
                    if attempts >= 100 { timer.invalidate(); panel.cancel(nil) }
                } else if attempts >= 100 {
                    timer.invalidate()
                    app.abortModal()
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            let actionDispatched = app.sendAction(NSSelectorFromString("saveFile:"), to: document, from: nil)
            timer.invalidate()
            let savedExists = FileManager.default.fileExists(atPath: expected.path)
            guard actionDispatched, result == "nativeSavePanel=true", let roots = try? readOwnJSON(expected),
                  roots.count == 1, roots[0].title == "Synthetic saved root",
                  window.title == "Untitled.mindmap.json — MindMap" else {
                finish("FAIL \(result) actionDispatched=\(actionDispatched) savedExists=\(savedExists) titleClean=\(window.title == "Untitled.mindmap.json — MindMap") attempts=\(attempts)", ok: false)
                return
            }
            finish("nativeSavePanel=true ownJSONDecoded=true nativeOpenPanel=unverified", ok: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: exercise)
        app.run()
    }
}
