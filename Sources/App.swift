import AppKit

final class MapCanvas: NSView, NSTextFieldDelegate {
    var model: MapModel { didSet { endEditingWithoutSaving(); needsDisplay = true } }
    var onChange: (() -> Void)?
    private var zoom: CGFloat = 1
    private var offset = CGPoint(x: 80, y: 90)
    private var editor: NSTextField?

    init(model: MapModel) {
        self.model = model
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view only") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func screen(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX * zoom + offset.x, y: frame.minY * zoom + offset.y,
               width: frame.width * zoom, height: frame.height * zoom)
    }
    private func visibleNodes() -> [LaidOutNode] { mapLayout(model.roots) }
    private func selectedNode() -> LaidOutNode? { visibleNodes().first { $0.node.id == model.selected } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.965, green: 0.973, blue: 0.982, alpha: 1).setFill()
        bounds.fill()
        let nodes = visibleNodes()
        if nodes.isEmpty {
            let message = "Empty map — open a .mindmap.json file to begin"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.secondaryLabelColor]
            (message as NSString).draw(at: CGPoint(x: 48, y: 60), withAttributes: attrs)
            return
        }
        for item in nodes {
            guard let parent = nodes.first(where: { $0.node.id == item.parent }) else { continue }
            let start = screen(parent.frame), end = screen(item.frame)
            let line = NSBezierPath()
            line.move(to: CGPoint(x: start.maxX, y: start.midY))
            line.curve(to: CGPoint(x: end.minX, y: end.midY),
                       controlPoint1: CGPoint(x: (start.maxX + end.minX) / 2, y: start.midY),
                       controlPoint2: CGPoint(x: (start.maxX + end.minX) / 2, y: end.midY))
            line.lineWidth = max(1, 1.5 * zoom)
            NSColor.systemTeal.withAlphaComponent(0.7).setStroke()
            line.stroke()
        }
        for item in nodes {
            let box = screen(item.frame)
            let shape = NSBezierPath(roundedRect: box, xRadius: 11 * zoom, yRadius: 11 * zoom)
            (item.node.id == model.selected ? NSColor.controlAccentColor : NSColor.white).setStroke()
            NSColor.white.setFill()
            shape.fill()
            shape.lineWidth = item.node.id == model.selected ? 3 : 1
            shape.stroke()
            if editor != nil && item.node.id == model.selected { continue }
            let title = item.node.title.isEmpty ? "New idea" : item.node.title
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(9, 14 * zoom), weight: .medium),
                .foregroundColor: item.node.title.isEmpty ? NSColor.gray : NSColor(calibratedWhite: 0.12, alpha: 1)
            ]
            let label = item.node.folded && !item.node.children.isEmpty ? "▸ " + title : title
            (label as NSString).draw(in: box.insetBy(dx: 12 * zoom, dy: 11 * zoom), withAttributes: attrs)
        }
    }

    private func beginEditing(replacing text: String? = nil) {
        guard editor == nil, let node = selectedNode() else { return }
        let field = NSTextField(frame: screen(node.frame).insetBy(dx: 10 * zoom, dy: 6 * zoom))
        field.stringValue = text ?? node.node.title
        field.font = .systemFont(ofSize: max(9, 14 * zoom))
        field.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
        editor = field
        window?.makeFirstResponder(field)
        if text == nil { field.currentEditor()?.selectAll(nil) }
        needsDisplay = true
    }

    private func endEditingWithoutSaving() {
        editor?.delegate = nil
        editor?.removeFromSuperview()
        editor = nil
        window?.makeFirstResponder(self)
    }
    func commitEditing() {
        guard let field = editor else { return }
        let title = field.stringValue
        endEditingWithoutSaving()
        if let node = selectedNode(), node.node.title != title {
            model.rename(title)
            changed()
        } else { needsDisplay = true }
    }
    private func changed() { needsDisplay = true; onChange?() }
    private func addChild() { commitEditing(); model.addChild(); changed(); beginEditing() }
    private func addSibling() { commitEditing(); let old = model.selected; model.addSibling(); if old != model.selected { changed(); beginEditing() } }
    func undo() { commitEditing(); model.undo(); needsDisplay = true; onChange?() }
    func redo() { commitEditing(); model.redo(); needsDisplay = true; onChange?() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertTab(_:)) { addChild(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) { addSibling(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { endEditingWithoutSaving(); needsDisplay = true; return true }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { commitEditing() }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers?.lowercased() == "z" {
                event.modifierFlags.contains(.shift) ? redo() : undo()
                return
            }
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 48: addChild()                         // Tab
        case 36, 76: addSibling()                   // Return / keypad Enter
        case 51, 117: commitEditing(); model.remove(); changed()
        case 49: commitEditing(); model.toggleFold(); changed()
        case 123, 124, 125, 126: moveSelection(event.keyCode)
        default:
            if let text = event.characters, !text.isEmpty,
               text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                beginEditing(replacing: text)
            } else { super.keyDown(with: event) }
        }
    }

    private func moveSelection(_ key: UInt16) {
        commitEditing()
        let nodes = visibleNodes()
        guard let current = nodes.first(where: { $0.node.id == model.selected }) else { return }
        let target: LaidOutNode?
        switch key {
        case 123: target = nodes.first { $0.node.id == current.parent }
        case 124: target = nodes.first { $0.parent == current.node.id }
        default:
            let direction: CGFloat = key == 125 ? 1 : -1
            target = nodes.filter { ($0.frame.midY - current.frame.midY) * direction > 0 }
                .min { a, b in
                    let aScore = abs(a.frame.midY - current.frame.midY) + abs(a.frame.midX - current.frame.midX) * 2
                    let bScore = abs(b.frame.midY - current.frame.midY) + abs(b.frame.midX - current.frame.midX) * 2
                    return aScore < bScore
                }
        }
        if let target { model.selected = target.node.id; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        commitEditing()
        let point = convert(event.locationInWindow, from: nil)
        if let node = visibleNodes().last(where: { screen($0.frame).contains(point) }) {
            model.selected = node.node.id
            needsDisplay = true
            if event.clickCount == 2 { beginEditing() }
        }
        window?.makeFirstResponder(editor ?? self)
    }
    override func mouseDragged(with event: NSEvent) {
        offset.x += event.deltaX
        offset.y -= event.deltaY
        editor?.frame = selectedNode().map { screen($0.frame).insetBy(dx: 10 * zoom, dy: 6 * zoom) } ?? .zero
        needsDisplay = true
    }
    private func zoom(at point: CGPoint, by factor: CGFloat) {
        let next = min(3, max(0.35, zoom * factor))
        offset.x = point.x - (point.x - offset.x) * next / zoom
        offset.y = point.y - (point.y - offset.y) * next / zoom
        zoom = next
        editor?.frame = selectedNode().map { screen($0.frame).insetBy(dx: 10 * zoom, dy: 6 * zoom) } ?? .zero
        needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            zoom(at: convert(event.locationInWindow, from: nil), by: exp(event.scrollingDeltaY * 0.01))
        } else {
            offset.x += event.scrollingDeltaX
            offset.y += event.scrollingDeltaY
            needsDisplay = true
        }
    }
    override func magnify(with event: NSEvent) {
        zoom(at: convert(event.locationInWindow, from: nil), by: 1 + event.magnification)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var canvas: MapCanvas!
    private var fileURL: URL?
    private var dirty = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = MapNode(id: UUID(), title: "Central idea", children: [], folded: false)
        canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        canvas.onChange = { [weak self] in self?.dirty = true; self?.updateTitle() }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Untitled — MindMap"
        window.contentView = canvas
        window.center()
        installMenu()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        confirmDiscardOrSave() ? .terminateNow : .terminateCancel
    }
    private func updateTitle() { window.title = "\(fileURL?.lastPathComponent ?? "Untitled")\(dirty ? " •" : "") — MindMap" }
    private func alert(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
    private func confirmDiscardOrSave() -> Bool {
        canvas.commitEditing()
        guard dirty else { return true }
        let prompt = NSAlert()
        prompt.messageText = "Save changes to this map?"
        prompt.informativeText = "Opening another file or quitting will discard unsaved changes."
        prompt.addButton(withTitle: "Save")
        prompt.addButton(withTitle: "Cancel")
        prompt.addButton(withTitle: "Discard Changes")
        switch prompt.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    @objc private func openFile(_ sender: Any?) {
        guard confirmDiscardOrSave() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.lastPathComponent.hasSuffix(".mindmap.json") else {
            alert("Unsupported format", detail: "Open only .mindmap.json files. Original .mindnode documents are not supported.")
            return
        }
        do {
            let roots = try JSONDecoder().decode([MapNode].self, from: Data(contentsOf: url))
            canvas.model = MapModel(roots: roots, selected: roots.first?.id ?? UUID())
            fileURL = url
            dirty = false
            updateTitle()
            window.makeFirstResponder(canvas)
        } catch { alert("Could not open map", detail: error.localizedDescription) }
    }
    @objc private func saveFile(_ sender: Any?) { _ = save() }
    private func save() -> Bool {
        canvas.commitEditing()
        var destination = fileURL
        if destination == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Untitled.mindmap.json"
            guard panel.runModal() == .OK else { return false }
            destination = panel.url
        }
        guard let url = destination, url.lastPathComponent.hasSuffix(".mindmap.json") else {
            alert("Unsupported format", detail: "Save only as .mindmap.json; original .mindnode documents cannot be overwritten.")
            return false
        }
        do {
            let data = try JSONEncoder().encode(canvas.model.roots)
            try data.write(to: url, options: .atomic)
            fileURL = url
            dirty = false
            updateTitle()
            return true
        } catch {
            alert("Could not save map", detail: error.localizedDescription)
            return false
        }
    }
    @objc private func undoEdit(_ sender: Any?) { canvas.undo() }
    @objc private func redoEdit(_ sender: Any?) { canvas.redo() }

    private func installMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MindMap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        main.addItem(app)
        let file = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openFile(_:)), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: "Save", action: #selector(saveFile(_:)), keyEquivalent: "s").target = self
        file.submenu = fileMenu
        main.addItem(file)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(undoEdit(_:)), keyEquivalent: "z").target = self
        let redo = editMenu.addItem(withTitle: "Redo", action: #selector(redoEdit(_:)), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = self
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }
}

@main
enum MindMapApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
