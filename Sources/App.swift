import AppKit

private final class MapNodeAX: NSAccessibilityElement {
    weak var canvas: MapCanvas?
    var nodeID: UUID?

    override func accessibilityPerformPress() -> Bool {
        guard let canvas, let nodeID else { return false }
        canvas.selectAndEdit(nodeID)
        return true
    }
}

final class MapCanvas: NSView, NSTextFieldDelegate {
    var model: MapModel { didSet { endEditingWithoutSaving(); revealSelection(); needsDisplay = true } }
    override var needsDisplay: Bool {
        didSet {
            let visibleIDs = Set(visibleNodes().map { $0.node.id })
            for (id, element) in accessibleNodes {
                element.setAccessibilitySelected(id == model.selected && visibleIDs.contains(id))
            }
            guard announcedSelection != model.selected else { return }
            announcedSelection = model.selected
            NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
            onSelectionChange?()
        }
    }
    var onChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    private var zoom: CGFloat = 1
    private var offset = CGPoint(x: 80, y: 90)
    private var editor: NSTextField?
    private var dragSource: UUID?
    private var dragPoint: CGPoint?
    private var dragOrigin: CGPoint?
    private var dragGrab = CGPoint.zero
    private var accessibleNodes: [UUID: MapNodeAX] = [:]
    private var announcedSelection: UUID

    init(model: MapModel) {
        self.model = model
        announcedSelection = model.selected
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view only") }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if editor != nil { revealSelection(); needsDisplay = true }
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? {
        let visible = visibleNodes()
        let ids = Set(visible.map { $0.node.id })
        accessibleNodes = accessibleNodes.filter { ids.contains($0.key) }
        let nodes: [MapNodeAX] = visible.map { item in
            let element = accessibleNodes[item.node.id] ?? MapNodeAX()
            accessibleNodes[item.node.id] = element
            element.canvas = self
            element.nodeID = item.node.id
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(item.node.title.isEmpty ? "New idea" : item.node.title)
            element.setAccessibilityHelp(item.node.children.isEmpty ? nil :
                "\(item.node.folded ? "Collapsed" : "Expanded"), \(item.node.children.count) child\(item.node.children.count == 1 ? "" : "ren")")
            element.setAccessibilitySelected(item.node.id == model.selected)
            element.setAccessibilityFrame(window?.convertToScreen(convert(screen(item.frame), to: nil)) ?? .zero)
            return element
        }
        return nodes + (super.accessibilityChildren() ?? [])
    }

    func selectNode(_ id: UUID) {
        commitEditing()
        guard visibleNodes().contains(where: { $0.node.id == id }) else { return }
        model.selected = id
        revealSelection()
        needsDisplay = true
    }

    func selectAndEdit(_ id: UUID) {
        selectNode(id)
        guard model.selected == id else { return }
        beginEditing()
    }

    private func screen(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX * zoom + offset.x, y: frame.minY * zoom + offset.y,
               width: frame.width * zoom, height: frame.height * zoom)
    }
    private func editorFrame(_ node: LaidOutNode) -> CGRect {
        let box = screen(node.frame)
        let width = min(max(120, (node.frame.width - 24) * max(zoom, 0.8)),
                        bounds.width > 128 ? bounds.width - 56 : .greatestFiniteMagnitude)
        let font = mapFont(isRoot: node.parent == nil, zoom: max(zoom, 0.8))
        let textHeight = (node.node.title as NSString).boundingRect(
            with: CGSize(width: width - 8, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
        let height = max(22, box.height - 22 * zoom, ceil(textHeight) + 6)
        // ponytail: a multiline editor taller than the viewport needs a scrollable text view.
        return CGRect(x: box.minX + 12 * zoom, y: box.midY - height / 2,
                      width: width, height: height)
    }
    @discardableResult
    func fitMapInView() -> CGRect {
        guard bounds.width > 128, bounds.height > 128 else { return .null }
        let nodes = visibleNodes()
        guard !nodes.isEmpty else { return .null }
        let world = nodes.reduce(CGRect.null) { $0.union($1.frame) }
        zoom = min(1, max(0.35, min((bounds.width - 128) / world.width,
                                     (bounds.height - 128) / world.height)))
        offset = CGPoint(x: bounds.midX - world.midX * zoom, y: bounds.midY - world.midY * zoom)
        let selected = nodes.first(where: { $0.node.id == model.selected })
        if let selected { editor?.font = mapFont(isRoot: selected.parent == nil, zoom: max(zoom, 0.8)) }
        editor?.frame = selected.map(editorFrame) ?? .zero
        needsDisplay = true
        return screen(world)
    }
    private func visibleNodes() -> [LaidOutNode] { mapLayout(model.roots) }
    private func selectedNode() -> LaidOutNode? { visibleNodes().first { $0.node.id == model.selected } }
    private func validDrop(at point: CGPoint, source: UUID, nodes: [LaidOutNode])
        -> (target: LaidOutNode, parent: UUID, index: Int)? {
        let local = CGPoint(x: (point.x - offset.x) / zoom, y: (point.y - offset.y) / zoom)
        if let target = nodes.last(where: { $0.node.id != source && screen($0.frame).contains(point) }) {
            let siblings = nodes.filter { $0.parent == target.parent }
            guard let place = dropPlacement(at: local, over: target, siblings: siblings),
                  model.canMoveNode(source, to: place.parent, at: place.index) else { return nil }
            return (target, place.parent, place.index)
        }
        // ponytail: visible sibling gaps only; arbitrary XY needs persisted coordinates and collision layout.
        for siblings in Dictionary(grouping: nodes.filter { $0.parent != nil }, by: { $0.parent! }).values {
            guard let index = siblings.firstIndex(where: { $0.frame.minY > local.y }), index > 0 else { continue }
            let before = siblings[index - 1], after = siblings[index]
            let beforeDistance = local.y - before.frame.maxY, afterDistance = after.frame.minY - local.y
            guard beforeDistance > 0, afterDistance > 0, min(beforeDistance, afterDistance) <= 24,
                  local.x >= min(before.frame.minX, after.frame.minX) - 20,
                  local.x <= max(before.frame.maxX, after.frame.maxX) + 20,
                  model.canMoveNode(source, to: after.parent!, at: index) else { continue }
            return (beforeDistance < afterDistance ? before : after, after.parent!, index)
        }
        return nil
    }
    private func revealSelection() {
        guard bounds.width > 64, bounds.height > 64, let node = selectedNode() else { return }
        let box = editor == nil ? screen(node.frame) : editorFrame(node), margin: CGFloat = 28
        if box.minX < bounds.minX + margin { offset.x += bounds.minX + margin - box.minX }
        else if box.maxX > bounds.maxX - margin { offset.x -= box.maxX - bounds.maxX + margin }
        if box.height > bounds.height - 2 * margin { offset.y += bounds.minY + margin - box.minY }
        else if box.minY < bounds.minY + margin { offset.y += bounds.minY + margin - box.minY }
        else if box.maxY > bounds.maxY - margin { offset.y -= box.maxY - bounds.maxY + margin }
        editor?.frame = selectedNode().map(editorFrame) ?? .zero
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let nodes = visibleNodes()
        let drop = dragSource.flatMap { source in
            dragPoint.flatMap { validDrop(at: $0, source: source, nodes: nodes) }
        }
        if nodes.isEmpty {
            let message = "Empty map — press Tab to create the first idea."
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
            let hovered = drop?.parent == item.node.id && drop?.target.node.id == item.node.id
            (item.node.id == model.selected || hovered ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            NSColor.controlBackgroundColor.setFill()
            shape.fill()
            shape.lineWidth = item.node.id == model.selected || hovered ? 3 : 1
            shape.stroke()
            if editor != nil && item.node.id == model.selected { continue }
            let title = item.node.title.isEmpty ? "New idea" : item.node.title
            let attrs: [NSAttributedString.Key: Any] = [
                .font: mapFont(isRoot: item.parent == nil, zoom: zoom),
                .foregroundColor: item.node.title.isEmpty ? NSColor.secondaryLabelColor : NSColor.labelColor
            ]
            let label = item.node.folded && !item.node.children.isEmpty ? "▸ " + title : title
            (label as NSString).draw(in: box.insetBy(dx: 12 * zoom, dy: 11 * zoom), withAttributes: attrs)
        }
        if let drop, drop.parent != drop.target.node.id, let dragPoint {
            let target = screen(drop.target.frame)
            let y = dragPoint.y < target.midY ? target.minY : target.maxY
            let indicator = NSBezierPath()
            indicator.move(to: CGPoint(x: target.minX - 8 * zoom, y: y))
            indicator.line(to: CGPoint(x: target.maxX + 8 * zoom, y: y))
            indicator.lineWidth = max(2, 3 * zoom)
            NSColor.controlAccentColor.setStroke()
            indicator.stroke()
        }
        if let dragPoint, let dragSource, let source = nodes.first(where: { $0.node.id == dragSource }) {
            let box = CGRect(x: dragPoint.x - dragGrab.x, y: dragPoint.y - dragGrab.y,
                             width: source.frame.width * zoom, height: source.frame.height * zoom)
            let ghost = NSBezierPath(roundedRect: box, xRadius: 11 * zoom, yRadius: 11 * zoom)
            NSColor.controlBackgroundColor.withAlphaComponent(0.88).setFill()
            ghost.fill()
            ghost.lineWidth = max(2, 2 * zoom)
            NSColor.controlAccentColor.setStroke()
            ghost.stroke()
            let title = source.node.title.isEmpty ? "New idea" : source.node.title
            let label = source.node.folded && !source.node.children.isEmpty ? "▸ " + title : title
            let attrs: [NSAttributedString.Key: Any] = [
                .font: mapFont(isRoot: source.parent == nil, zoom: zoom),
                .foregroundColor: NSColor.labelColor
            ]
            (label as NSString).draw(in: box.insetBy(dx: 12 * zoom, dy: 11 * zoom), withAttributes: attrs)
        }
    }

    private func beginEditing() {
        guard editor == nil else { return }
        revealSelection()
        guard let node = selectedNode() else { return }
        let field = NSTextField(frame: editorFrame(node))
        field.stringValue = node.node.title
        field.font = mapFont(isRoot: node.parent == nil, zoom: max(zoom, 0.8))
        field.textColor = .labelColor
        field.isBordered = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType = .default
        field.delegate = self
        addSubview(field)
        editor = field
        revealSelection()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
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
    private func changed() { revealSelection(); needsDisplay = true; onChange?() }
    func addChild() { commitEditing(); model.addChild(); changed(); beginEditing() }
    func addSibling(before: Bool = false) { commitEditing(); let old = model.selected; model.addSibling(before: before); if old != model.selected { changed(); beginEditing() } }
    func addParent() { commitEditing(); let old = model.selected; model.addParent(); if old != model.selected { changed(); beginEditing() } }
    func addMainNode() { commitEditing(); model.addMainNode(); changed(); beginEditing() }
    func detachSelected() { commitEditing(); if model.detachSelected() { changed() } }
    func undo() { commitEditing(); if model.undo() { changed() } }
    func redo() { commitEditing(); if model.redo() { changed() } }
    func toggleFold() { commitEditing(); if model.toggleFold() { changed() } }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertTabIgnoringFieldEditor(_:)) { addParent(); return true }
        if selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) { addSibling(before: true); return true }
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        if selector == #selector(NSResponder.insertTab(_:)) {
            modifiers.contains(.option) ? addParent() : addChild()
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if modifiers.contains(.shift) { addMainNode() }
            else { addSibling(before: modifiers.contains(.option)) }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) { endEditingWithoutSaving(); needsDisplay = true; return true }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { commitEditing() }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control),
               [UInt16(125), 126].contains(event.keyCode) {
                commitEditing()
                if model.moveSibling(by: event.keyCode == 126 ? -1 : 1) { changed() }
                return
            }
            if event.charactersIgnoringModifiers?.lowercased() == "d",
               event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) {
                detachSelected()
                return
            }
            if event.charactersIgnoringModifiers?.lowercased() == "z" {
                event.modifierFlags.contains(.shift) ? redo() : undo()
                return
            }
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 53 where dragSource != nil:
            dragSource = nil; dragPoint = nil; dragOrigin = nil; needsDisplay = true
        case 48 where event.modifierFlags.contains(.option): addParent()
        case 48: addChild()                         // Tab
        case 36, 76:
            if event.modifierFlags.contains(.shift) { addMainNode() }
            else { addSibling(before: event.modifierFlags.contains(.option)) }
        case 51, 117: commitEditing(); if model.remove() { changed() }
        case 49: toggleFold() // Optional Space
        case 47 where event.modifierFlags.contains(.option): toggleFold() // Static original menu: Option+period
        case 123, 124, 125, 126: moveSelection(event.keyCode)
        default:
            if let text = event.characters, !text.isEmpty,
               text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                beginEditing()
                editor?.currentEditor()?.keyDown(with: event)
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
        if let target { model.selected = target.node.id; revealSelection(); needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        commitEditing()
        dragSource = nil
        dragPoint = nil
        let point = convert(event.locationInWindow, from: nil)
        dragOrigin = point
        if let node = visibleNodes().last(where: { screen($0.frame).contains(point) }) {
            model.selected = node.node.id
            dragSource = event.clickCount == 1 && node.parent != nil ? node.node.id : nil
            let box = screen(node.frame)
            dragGrab = CGPoint(x: point.x - box.minX, y: point.y - box.minY)
            needsDisplay = true
            if event.clickCount == 2 { beginEditing() }
        }
        if editor == nil { window?.makeFirstResponder(self) }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if dragSource != nil {
            if dragPoint == nil, let origin = dragOrigin,
               hypot(point.x - origin.x, point.y - origin.y) < 9 { return }
            dragPoint = point
            needsDisplay = true
            return
        }
        if let origin = dragOrigin {
            offset.x += point.x - origin.x
            offset.y += point.y - origin.y
            dragOrigin = point
            editor?.frame = selectedNode().map(editorFrame) ?? .zero
            needsDisplay = true
        }
    }
    override func mouseUp(with event: NSEvent) {
        defer { dragSource = nil; dragPoint = nil; dragOrigin = nil; needsDisplay = true }
        guard let source = dragSource, dragPoint != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let placement = validDrop(at: point, source: source, nodes: visibleNodes()),
           model.moveNode(source, to: placement.parent, at: placement.index) { changed() }
    }
    private func zoom(at point: CGPoint, by factor: CGFloat) {
        let next = min(3, max(0.35, zoom * factor))
        offset.x = point.x - (point.x - offset.x) * next / zoom
        offset.y = point.y - (point.y - offset.y) * next / zoom
        zoom = next
        let selected = selectedNode()
        if let selected { editor?.font = mapFont(isRoot: selected.parent == nil, zoom: max(zoom, 0.8)) }
        editor?.frame = selected.map(editorFrame) ?? .zero
        needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            zoom(at: convert(event.locationInWindow, from: nil), by: exp(event.scrollingDeltaY * 0.01))
        } else {
            offset.x += event.scrollingDeltaX
            offset.y += event.scrollingDeltaY
            editor?.frame = selectedNode().map(editorFrame) ?? .zero
            needsDisplay = true
        }
    }
    override func magnify(with event: NSEvent) {
        zoom(at: convert(event.locationInWindow, from: nil), by: 1 + event.magnification)
    }
}

#if HEADLESS_TEST
private func ownedPanelFixtureDirectory() -> URL? {
    guard let path = ProcessInfo.processInfo.environment["MINDMAP_SELFTEST_PANEL_DIR"] else { return nil }
    let directory = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
    guard directory.lastPathComponent.hasPrefix("mindmap-native-panel-"),
          (try? String(contentsOf: directory.appendingPathComponent(".owner"), encoding: .utf8)) == "mindmap-owned-native-panel\n",
          attributes?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
          (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { return nil }
    return directory
}
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSOpenSavePanelDelegate, NSToolbarDelegate {
    private var window: NSWindow!
    private var canvas: MapCanvas!
    private var outline: MapOutlineView!
    private var splitController: NSSplitViewController!
    private var fileURL: URL?
    private var savedRoots: [MapNode] = []
    private var dirty = false
    private var closeApproved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = MapNode(id: UUID(), title: "Central idea", children: [], folded: false)
        canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        savedRoots = [root]
        _ = makeWorkbench(canvas: canvas)
        canvas.onChange = { [weak self] in self?.syncDirty(); self?.outline.reloadMap() }
        canvas.onSelectionChange = { [weak self] in self?.outline.syncSelection() }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Untitled — MindMap"
        window.delegate = self
        window.minSize = NSSize(width: 640, height: 400)
        window.contentViewController = splitController
        window.toolbar = makeToolbar()
        window.center()
        installMenu()
        window.contentView?.layoutSubtreeIfNeeded()
        canvas.fitMapInView()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard confirmDiscardOrSave() else { return false }
        closeApproved = true
        NSApp.terminate(nil) // Exit the single-window app instead of stranding its map.
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        closeApproved || confirmDiscardOrSave() ? .terminateNow : .terminateCancel
    }
    private func syncDirty() {
        // ponytail: O(nodes) comparison per edit; use revision IDs if large-map editing becomes slow.
        dirty = canvas.model.roots != savedRoots
        updateTitle()
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
        prompt.informativeText = "Opening another file, closing the window, or quitting will discard unsaved changes."
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
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.lastPathComponent.hasSuffix(".mindmap.json") else {
            alert("Unsupported format", detail: "Select an existing .mindmap.json file; use Open MindNode for a read-only import.")
            return
        }
        do {
            _ = try readOwnJSON(url) // Reject invalid files without prompting to discard edits.
            guard confirmDiscardOrSave() else { return }
            // Saving may have changed this same path; never install the pre-save tree.
            let roots = try readOwnJSON(url)
            canvas.model = MapModel(roots: roots, selected: roots.first?.id ?? UUID())
            outline.reloadMap()
            fileURL = url
            savedRoots = roots
            dirty = false
            updateTitle()
            canvas.fitMapInView()
            window.makeFirstResponder(canvas)
        } catch { alert("Could not open map", detail: error.localizedDescription) }
    }
    @objc private func openMindNode(_ sender: Any?) {
        let panel = NSOpenPanel()
        // The installed MindNode UTType conforms to .data, not .package or .directory.
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.delegate = self
        panel.message = "Select a MindNode v9 directory package. Import is read-only; Save creates a new .mindmap.json file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let roots = try MindNodeImporter.load(url)
            guard confirmDiscardOrSave() else { return }
            canvas.model = MapModel(roots: roots, selected: roots.first?.id ?? UUID())
            outline.reloadMap()
            fileURL = nil // Never save into the source package.
            savedRoots = roots
            dirty = false
            updateTitle()
            canvas.fitMapInView()
            window.makeFirstResponder(canvas)
            alert("MindNode imported read-only", detail: "Only text, tree structure and fold state were copied. Styles, notes and attachments are not round-tripped. Save creates a new .mindmap.json file; it never overwrites the MindNode package.")
        } catch { alert("Could not open MindNode", detail: error.localizedDescription) }
    }
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    func panel(_ sender: Any, validate url: URL) throws {
        guard url.pathExtension.lowercased() == "mindnode",
              (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeDirectory else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnsupportedSchemeError,
                          userInfo: [NSLocalizedDescriptionKey: "Select a .mindnode directory package, not an ordinary folder."])
        }
    }
    @objc private func saveFile(_ sender: Any?) { _ = save() }
    private func save() -> Bool {
        canvas.commitEditing()
        var destination = fileURL
        if destination == nil {
            let panel = NSSavePanel()
            #if HEADLESS_TEST
            guard let directory = ownedPanelFixtureDirectory() else { return false }
            panel.directoryURL = directory
            #endif
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Untitled.mindmap.json"
            guard panel.runModal() == .OK else { return false }
            destination = panel.url
        }
        guard let url = destination, url.lastPathComponent.hasSuffix(".mindmap.json") else {
            alert("Unsupported format", detail: "Save only as .mindmap.json; original .mindnode documents cannot be overwritten.")
            return false
        }
        #if HEADLESS_TEST
        guard let directory = ownedPanelFixtureDirectory(),
              url.standardizedFileURL == directory.appendingPathComponent("Untitled.mindmap.json").standardizedFileURL else { return false }
        #endif
        do {
            try writeOwnJSON(canvas.model.roots, to: url)
            fileURL = url
            savedRoots = canvas.model.roots
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
    @objc private func newChild(_ sender: Any?) { canvas.addChild() }
    @objc private func newSibling(_ sender: Any?) { canvas.addSibling() }
    @objc private func newSiblingBefore(_ sender: Any?) { canvas.addSibling(before: true) }
    @objc private func newParent(_ sender: Any?) { canvas.addParent() }
    @objc private func newMainNode(_ sender: Any?) { canvas.addMainNode() }
    @objc private func detachNode(_ sender: Any?) { canvas.detachSelected() }
    @objc private func foldNode(_ sender: Any?) { canvas.toggleFold() }
    @objc private func fitMap(_ sender: Any?) { canvas.fitMapInView() }

    func makeWorkbench(canvas: MapCanvas) -> NSSplitViewController {
        let split = NSSplitViewController()
        let sidebarController = NSViewController()
        outline = MapOutlineView(canvas: canvas)
        sidebarController.view = outline
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebar.canCollapse = true
        sidebar.minimumThickness = 180
        sidebar.maximumThickness = 320
        split.addSplitViewItem(sidebar)
        let canvasController = NSViewController()
        canvasController.view = canvas
        split.addSplitViewItem(NSSplitViewItem(viewController: canvasController))
        splitController = split
        return split
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MindMap")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        return toolbar
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("new-child"), .init("new-sibling"), .init("fold-node"), .init("fit-map"),
         .flexibleSpace, .init("undo"), .init("redo")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let details: (String, String, Selector)
        switch identifier.rawValue {
        case "new-child": details = ("New Child", "plus", #selector(newChild(_:)))
        case "new-sibling": details = ("New Sibling", "arrow.turn.down.right", #selector(newSibling(_:)))
        case "fold-node": details = ("Fold/Unfold", "chevron.right", #selector(foldNode(_:)))
        case "fit-map": details = ("Fit Map", "arrow.up.left.and.arrow.down.right", #selector(fitMap(_:)))
        case "undo": details = ("Undo", "arrow.uturn.backward", #selector(undoEdit(_:)))
        case "redo": details = ("Redo", "arrow.uturn.forward", #selector(redoEdit(_:)))
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = details.0
        item.paletteLabel = details.0
        item.toolTip = details.0
        item.image = NSImage(systemSymbolName: details.1, accessibilityDescription: details.0)
        item.target = self
        item.action = details.2
        return item
    }

    func installMenu() {
        let main = NSMenu()
        let app = NSMenuItem(title: "MindMap", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MindMap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        main.addItem(app)
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open MindNode (Read-only)…", action: #selector(openMindNode(_:)), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: "Open Own JSON…", action: #selector(openFile(_:)), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Save", action: #selector(saveFile(_:)), keyEquivalent: "s").target = self
        file.submenu = fileMenu
        main.addItem(file)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(undoEdit(_:)), keyEquivalent: "z").target = self
        let redo = editMenu.addItem(withTitle: "Redo", action: #selector(redoEdit(_:)), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = self
        edit.submenu = editMenu
        main.addItem(edit)
        let view = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        let outlineItem = viewMenu.addItem(withTitle: "Show/Hide Outline",
            action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        outlineItem.keyEquivalentModifierMask = [.option, .command]
        outlineItem.target = splitController
        view.submenu = viewMenu
        main.addItem(view)
        let node = NSMenuItem(title: "Node", action: nil, keyEquivalent: "")
        let nodeMenu = NSMenu(title: "Node")
        let entries: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("New Child", #selector(newChild(_:)), "\t", []),
            ("New Sibling", #selector(newSibling(_:)), "\r", []),
            ("New Sibling Before", #selector(newSiblingBefore(_:)), "\r", [.option]),
            ("New Parent", #selector(newParent(_:)), "\t", [.option]),
            ("New Main Node", #selector(newMainNode(_:)), "\r", [.shift]),
            ("Detach Node", #selector(detachNode(_:)), "D", [.command, .shift])
        ]
        for (title, action, key, modifiers) in entries {
            let item = nodeMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
        }
        node.submenu = nodeMenu
        main.addItem(node)
        NSApp.mainMenu = main
    }
}

#if !HEADLESS_TEST
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
#endif
