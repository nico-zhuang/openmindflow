import AppKit

enum DocumentTabOrientation: String { case horizontal, vertical }

/// The tab control is outside each document's three-pane workbench.
final class DocumentTabStrip: NSView, NSTextFieldDelegate {
    var orientation: DocumentTabOrientation = .horizontal { didSet { needsLayout = true } }
    var documents: [DocumentSession] = [] { didSet { rebuild() } }
    var selectedID: UUID? { didSet { rebuild() } }
    var onSelect: (UUID) -> Void = { _ in }
    var onClose: (UUID) -> Void = { _ in }
    var onNewTab: () -> Void = {}
    var onOrientationChange: (DocumentTabOrientation) -> Void = { _ in }
    var defaults: UserDefaults = .standard { didSet { rebuild() } }
    weak var transfer: DocumentTabTransfer?
    // Each source gesture owns its own signal, so canceled UUIDs cannot accumulate across drags.
    private var releaseSignal: DragReleaseSignal?
    private var draggingToken: UUID?
    private(set) var previewIndex: Int? { didSet { needsDisplay = true } }
    private var identifiers: [ObjectIdentifier: UUID] = [:]
    private var rows: [(document: DocumentSession, view: NSView)] = []
    private weak var editingDocument: DocumentSession?
    private weak var titleEditor: NSTextField?
    private var cancelEditing = false
    private var pendingEditorText: String?
    private let addButton = NSButton(title: "+", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addButton.bezelStyle = .texturedRounded
        addButton.target = self
        addButton.action = #selector(addTab(_:))
        addSubview(addButton)
        registerForDraggedTypes([DocumentTabTransfer.pasteboardType])
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view only") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .tabGroup }
    func id(for document: DocumentSession) -> UUID {
        let key = ObjectIdentifier(document)
        if let id = identifiers[key] { return id }
        let id = UUID()
        identifiers[key] = id
        return id
    }
    func localize() { rebuild() }
    private func rebuild() {
        if titleEditor != nil, let owner = liveOwner, editingDocument?.window === owner.window,
           rows.count == documents.count,
           zip(rows, documents).allSatisfy({ $0.document === $1 }) {
            for row in rows {
                (row.view as? TabChromeRow)?.selected = selectedID == id(for: row.document)
                guard let title = row.view.subviews.first as? DragTabButton,
                      let close = row.view.subviews.dropFirst().first as? NSButton else { continue }
                let name = row.document.displayTabTitle(defaults: defaults)
                title.title = name + (row.document.dirty ? " •" : "")
                title.state = selectedID == id(for: row.document) ? .on : .off
                title.setAccessibilityLabel(name + (row.document.dirty ? ", " + L10n.text("Modified", defaults: defaults) : ""))
                title.setAccessibilityCloseName(L10n.text("Close Tab", defaults: defaults))
                close.setAccessibilityLabel(L10n.text("Close Tab", defaults: defaults) + ": " + name)
            }
            addButton.setAccessibilityLabel(L10n.text("New Tab", defaults: defaults))
            return // Keep the live field, but refresh sibling chrome and AX metadata.
        }
        if let field = titleEditor {
            let document = editingDocument
            let text = pendingEditorText ?? field.currentEditor()?.string ?? field.stringValue
            titleEditor = nil
            editingDocument = nil
            pendingEditorText = nil
            field.delegate = nil
            field.removeFromSuperview()
            if let document, let owner = liveOwner,
               owner.documents.contains(where: { $0 === document }), document.window === owner.window,
               !cancelEditing, NativeMapFile.normalizedTabTitle(text) != nil {
                _ = document.renameTab(to: text)
            }
            cancelEditing = false
        }
        titleEditor = nil
        editingDocument = nil
        for row in rows { row.view.removeFromSuperview() }
        rows.removeAll()
        let live = Set(documents.map(ObjectIdentifier.init))
        identifiers = identifiers.filter { live.contains($0.key) }
        for document in documents {
            let id = id(for: document)
            let row = TabChromeRow(frame: .zero)
            row.selected = selectedID == id
            let name = document.displayTabTitle(defaults: defaults)
            let title = DragTabButton(title: name + (document.dirty ? " •" : ""), target: self,
                                     action: #selector(selectTab(_:)))
            title.strip = self
            title.onCloseAccessibility = { [weak self, weak title] in
                guard let self, let title else { return false }
                return self.requestClose(from: title)
            }
            title.setAccessibilityCloseName(L10n.text("Close Tab", defaults: defaults))
            title.isBordered = false
            title.setAccessibilityLabel(name + (document.dirty ? ", " + L10n.text("Modified", defaults: defaults) : ""))
            title.setAccessibilityRole(.radioButton)
            title.state = selectedID == id ? .on : .off
            row.addSubview(title)
            let close = NSButton(title: "×", target: self, action: #selector(closeTab(_:)))
            close.bezelStyle = .recessed
            close.font = .systemFont(ofSize: 15, weight: .regular)
            close.contentTintColor = .secondaryLabelColor
            close.isHidden = true
            close.alphaValue = 0
            row.onHover = { [weak row, weak close] hovered in
                guard let row, let close, row.superview != nil else { return }
                row.hovered = hovered
                row.hoverGeneration &+= 1
                let generation = row.hoverGeneration
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    close.alphaValue = hovered ? 1 : 0
                    close.isHidden = !hovered
                    return
                }
                close.isHidden = false
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    close.animator().alphaValue = hovered ? 1 : 0
                } completionHandler: { [weak row, weak close] in
                    guard let row, let close, row.superview != nil,
                          row.hoverGeneration == generation, !row.hovered else { return }
                    close.isHidden = true
                }
            }
            close.setAccessibilityLabel(L10n.text("Close Tab", defaults: defaults) + ": " + name)
            row.addSubview(close)
            addSubview(row)
            rows.append((document, row))
        }
        addButton.setAccessibilityLabel(L10n.text("New Tab", defaults: defaults))
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let horizontal = orientation == .horizontal
        let extent: CGFloat = horizontal ? 154 : 35
        for (index, row) in rows.enumerated() {
            row.view.frame = horizontal ? CGRect(x: CGFloat(index) * extent, y: 0, width: extent, height: bounds.height)
                                        : CGRect(x: 0, y: CGFloat(index) * extent, width: bounds.width, height: extent)
            let title = row.view.subviews[0], close = row.view.subviews[1]
            title.frame = CGRect(x: 4, y: 3, width: max(30, row.view.bounds.width - 32), height: row.view.bounds.height - 6)
            close.frame = CGRect(x: row.view.bounds.width - 28, y: max(0, (row.view.bounds.height - 26) / 2), width: 24, height: 26)
        }
        addButton.frame = horizontal ? CGRect(x: CGFloat(rows.count) * extent + 4, y: 3, width: 30, height: bounds.height - 6)
                                     : CGRect(x: (bounds.width - 30) / 2, y: CGFloat(rows.count) * extent + 3, width: 30, height: 29)
    }
    func insertionIndex(at point: CGPoint) -> Int {
        let coordinate = orientation == .horizontal ? point.x : point.y
        let extent: CGFloat = orientation == .horizontal ? 154 : 35
        // The insertion boundary is the midpoint of each live tab, in either layout.
        for index in documents.indices where coordinate < (CGFloat(index) + 0.5) * extent {
            return index
        }
        return documents.count
    }
    func token(from pasteboard: NSPasteboard) -> UUID? {
        guard liveOwner != nil, let transfer,
              let items = pasteboard.pasteboardItems, items.count == 1,
              items[0].types == [DocumentTabTransfer.pasteboardType],
              let bytes = items[0].data(forType: DocumentTabTransfer.pasteboardType), bytes.count == 36,
              let text = String(data: bytes, encoding: .utf8),
              let token = UUID(uuidString: text), token.uuidString == text,
              transfer.liveSource(for: token) != nil else { return nil }
        return token
    }
    func previewInsertion(token: UUID, at point: CGPoint) -> Int? {
        guard bounds.contains(point), let owner = liveOwner,
              transfer?.canAccept(token: token, in: owner) == true else {
            cancelInsertionPreview(); return nil
        }
        let index = insertionIndex(at: point)
        previewIndex = index
        return index
    }
    func cancelInsertionPreview() { previewIndex = nil }
    @discardableResult func accept(token: UUID, at point: CGPoint) -> Bool {
        guard let index = previewInsertion(token: token, at: point),
              let owner = liveOwner, let source = transfer?.liveSource(for: token),
              transfer?.move(token: token, to: owner, insertion: index) == true else {
            cancelInsertionPreview(); return false
        }
        source.tabStrip.finishAcceptedDrag(token: token)
        cancelInsertionPreview()
        return true
    }
    private func finishAcceptedDrag(token: UUID) {
        if draggingToken == token { cancelNativeDrag() }
    }
    func cancelNativeDrag() {
        guard let token = draggingToken else { return }
        if let signal = releaseSignal {
            signal.disarm(token: token)
            if DocumentDragApplication.activeReleaseSignal === signal {
                DocumentDragApplication.activeReleaseSignal = nil
            }
        }
        releaseSignal = nil
        draggingToken = nil
        transfer?.cancel(token: token)
        cancelInsertionPreview()
        for owner in transfer?.eligibleWindows?() ?? [] { owner.tabStrip.cancelInsertionPreview() }
    }
    func armNativeDrag(document: DocumentSession, source: WindowSession,
                       after timestamp: TimeInterval) -> UUID? {
        guard draggingToken == nil, releaseSignal == nil,
              DocumentDragApplication.activeReleaseSignal == nil,
              liveOwner === source, document.window === source.window,
              source.documents.contains(where: { $0 === document }), let transfer else { return nil }
        let token = transfer.begin(document: document, source: source)
        guard transfer.liveSource(for: token) === source else {
            transfer.cancel(token: token); return nil
        }
        let signal = DragReleaseSignal()
        draggingToken = token
        releaseSignal = signal
        signal.arm(token: token, after: timestamp, sourceWindowNumber: source.window.windowNumber)
        DocumentDragApplication.activeReleaseSignal = signal
        return token
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let index = previewIndex else { return }
        NSColor.controlAccentColor.setFill()
        if orientation == .horizontal {
            CGRect(x: CGFloat(index) * 154 - 1, y: 1, width: 3, height: max(0, bounds.height - 2)).fill()
        } else {
            CGRect(x: 1, y: CGFloat(index) * 35 - 1, width: max(0, bounds.width - 2), height: 3).fill()
        }
    }
    @discardableResult func beginNativeDrag(from button: NSButton, event: NSEvent) -> Bool {
        guard window?.isVisible == true, let owner = liveOwner,
              let document = liveDocument(for: button, controlIndex: 0),
              let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds),
              let token = armNativeDrag(document: document, source: owner,
                                        after: event.timestamp) else { return false }
        let item = NSPasteboardItem()
        guard item.setData(Data(token.uuidString.utf8), forType: DocumentTabTransfer.pasteboardType) else {
            cancelNativeDrag(); return false
        }
        button.cacheDisplay(in: button.bounds, to: bitmap)
        let image = NSImage(size: button.bounds.size)
        image.addRepresentation(bitmap)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(button.convert(button.bounds, to: self), contents: image)
        _ = beginDraggingSession(with: [dragging], event: event, source: self)
        return true
    }
    private func liveDocument(for sender: NSButton, controlIndex: Int) -> DocumentSession? {
        guard let row = rows.first(where: {
            $0.view === sender.superview && $0.view.superview === self &&
            $0.view.subviews.indices.contains(controlIndex) && $0.view.subviews[controlIndex] === sender
        }), documents.contains(where: { $0 === row.document }) else { return nil }
        return row.document
    }
    fileprivate func beginInlineRename(from sender: NSButton) {
        guard titleEditor == nil, let document = liveDocument(for: sender, controlIndex: 0),
              liveOwner != nil, let row = sender.superview else { return }
        let field = NSTextField(frame: sender.frame)
        field.stringValue = document.displayTabTitle(defaults: defaults)
        field.delegate = self
        field.font = sender.font
        field.setAccessibilityLabel(L10n.text("Rename Tab", defaults: defaults))
        row.addSubview(field, positioned: .above, relativeTo: sender)
        editingDocument = document
        pendingEditorText = nil
        titleEditor = field
        _ = window?.makeFirstResponder(field)
        // A visible non-key window cannot host a field editor in an accessory process.
        // Selecting there sends a premature end-editing notification and removes this field.
        if window?.isKeyWindow == true, let activeEditor = field.currentEditor(),
           window?.firstResponder === activeEditor { field.selectText(nil) }
    }
    fileprivate func selectAfterEditorBlur(from sender: NSButton) -> Bool {
        guard let editor = titleEditor, let document = liveDocument(for: sender, controlIndex: 0),
              editingDocument !== document else { return false }
        guard NativeMapFile.normalizedTabTitle(editor.currentEditor()?.string ?? editor.stringValue) != nil,
              window?.makeFirstResponder(self) == true else { return true }
        // The blur rebuilds the original button before its mouse-up; deliver this click once.
        if let current = liveOwner, current.documents.contains(where: { $0 === document }) {
            onSelect(id(for: document))
        }
        return true
    }
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        guard control === titleEditor else { return true }
        guard !cancelEditing else { return true }
        guard NativeMapFile.normalizedTabTitle(fieldEditor.string) != nil else {
            pendingEditorText = nil
            return false
        }
        pendingEditorText = fieldEditor.string
        return true
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === titleEditor else { return }
        let document = editingDocument
        let canceled = cancelEditing
        let committedText = pendingEditorText ?? field.stringValue
        titleEditor = nil
        editingDocument = nil
        cancelEditing = false
        pendingEditorText = nil
        field.removeFromSuperview()
        guard !canceled, let document, let owner = liveOwner,
              owner.documents.contains(where: { $0 === document }), document.window === owner.window else { return }
        _ = document.renameTab(to: committedText)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === titleEditor else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing = true
            window?.makeFirstResponder(self)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if NativeMapFile.normalizedTabTitle(textView.string) != nil {
                pendingEditorText = textView.string
                window?.makeFirstResponder(self)
            } else { pendingEditorText = nil }
            return true
        }
        return false
    }
    private func requestClose(from sender: NSButton) -> Bool {
        guard let document = liveDocument(for: sender, controlIndex: 0), liveOwner != nil else { return false }
        onClose(id(for: document))
        return true
    }
    @objc private func selectTab(_ sender: NSButton) {
        guard let document = liveDocument(for: sender, controlIndex: 0) else { return }
        onSelect(id(for: document))
    }
    @objc private func closeTab(_ sender: NSButton) {
        guard let document = liveDocument(for: sender, controlIndex: 1) else { return }
        onClose(id(for: document))
    }
    @objc private func addTab(_ sender: NSButton) { onNewTab() }
    private var liveOwner: WindowSession? {
        guard let owner = window?.delegate as? WindowSession,
              owner.isTransferLive, owner.tabStrip === self else { return nil }
        return owner
    }
    @discardableResult private func requestOrientation(_ value: DocumentTabOrientation) -> Bool {
        guard liveOwner != nil else { return false }
        onOrientationChange(value)
        return true
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [DocumentTabOrientation.horizontal, .vertical].map { choice in
            NSAccessibilityCustomAction(name: L10n.text(choice == .horizontal ? "Horizontal Tabs" : "Vertical Tabs", defaults: defaults)) { [weak self] in
                self?.requestOrientation(choice) ?? false
            }
        }
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard liveOwner != nil, let window, window.isVisible, window.isKeyWindow,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
        return orientationMenu().popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.midY), in: self)
    }
    override func keyDown(with event: NSEvent) {
        if window?.firstResponder === self, event.keyCode == 109,
           event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.shift],
           accessibilityPerformShowMenu() { return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? { orientationMenu() }
    private func orientationMenu() -> NSMenu {
        let menu = NSMenu()
        for choice in [DocumentTabOrientation.horizontal, .vertical] {
            let item = menu.addItem(withTitle: L10n.text(choice == .horizontal ? "Horizontal Tabs" : "Vertical Tabs", defaults: defaults),
                                    action: #selector(selectOrientation(_:)),
                                     keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == orientation ? .on : .off
        }
        return menu
    }
    @objc private func selectOrientation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let value = DocumentTabOrientation(rawValue: raw) else { return }
        _ = requestOrientation(value)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let token = token(from: sender.draggingPasteboard),
              let source = transfer?.liveSource(for: token),
              sender.draggingSource as AnyObject? === source.tabStrip,
              sender.draggingSourceOperationMask.contains(.move),
              previewInsertion(token: token, at: convert(sender.draggingLocation, from: nil)) != nil else {
            cancelInsertionPreview(); return []
        }
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { cancelInsertionPreview() }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard draggingUpdated(sender) == .move,
              let token = token(from: sender.draggingPasteboard) else { return false }
        return accept(token: token, at: convert(sender.draggingLocation, from: nil))
    }
    override func draggingEnded(_ sender: NSDraggingInfo) { cancelInsertionPreview() }
}

extension DocumentTabStrip: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let token = draggingToken, let signal = releaseSignal else { return }
        defer { cancelNativeDrag() }
        _ = transfer?.finish(token: token, locationOnScreen: screenPoint, operation: operation, signal: signal)
    }
}

/// Draw in the row itself, leaving the title button's native action and dragging intact.
private final class TabChromeRow: NSView {
    var selected = false { didSet { needsDisplay = true } }
    var hovered = false
    var hoverGeneration: UInt64 = 0
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard selected else { return }
        let area = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: area, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.23).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.78).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

/// Native button actions remain keyboard/AX-clickable; only pointer motion enters AppKit drag.
private final class DragTabButton: NSButton {
    weak var strip: DocumentTabStrip?
    var onCloseAccessibility: (() -> Bool)?
    private var closeAccessibilityName = "Close Tab"
    func setAccessibilityCloseName(_ name: String) { closeAccessibilityName = name }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [NSAccessibilityCustomAction(name: closeAccessibilityName) { [weak self] in
            self?.onCloseAccessibility?() ?? false
        }]
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { strip?.beginInlineRename(from: self); return }
        if strip?.selectAfterEditorBlur(from: self) == true { return }
        let origin = convert(event.locationInWindow, from: nil)
        isHighlighted = true
        defer { isHighlighted = false }
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                                         until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .keyDown {
                // Never swallow menu shortcuts just because the title button owns pointer tracking.
                if next.keyCode != 53 { NSApp.sendEvent(next) }
                return // Escape cancels without forwarding the drag-start gesture.
            }
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { performClick(nil) }
                return
            }
            let point = convert(next.locationInWindow, from: nil)
            guard hypot(point.x - origin.x, point.y - origin.y) >= 8 else { continue }
            if strip?.beginNativeDrag(from: self, event: next) == true { return }
            return
        }
    }
}

/// Owns layout only; the active split remains a real child view controller.
final class DocumentTabRoot: NSViewController {
    let strip: DocumentTabStrip
    private(set) var workbench: NSSplitViewController?
    init(strip: DocumentTabStrip) {
        self.strip = strip
        super.init(nibName: nil, bundle: nil)
        view = DocumentTabRootView(strip: strip)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view only") }
    var layoutView: DocumentTabRootView { view as! DocumentTabRootView }
    func display(_ split: NSSplitViewController?) {
        // Reparenting may already have detached this split into another window.
        if let workbench, workbench.parent === self {
            workbench.view.removeFromSuperview()
            workbench.removeFromParent()
        }
        workbench = split
        if let split {
            addChild(split)
            layoutView.addSubview(split.view)
            layoutView.workbench = split.view
        } else { layoutView.workbench = nil }
        layoutView.needsLayout = true
        layoutView.layoutSubtreeIfNeeded()
    }
}

final class DocumentTabRootView: NSView {
    let strip: DocumentTabStrip
    weak var workbench: NSView?
    init(strip: DocumentTabStrip) {
        self.strip = strip
        super.init(frame: .zero)
        addSubview(strip)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view only") }
    override func layout() {
        super.layout()
        if strip.orientation == .horizontal {
            strip.frame = CGRect(x: 0, y: max(0, bounds.height - 36), width: bounds.width, height: 36)
            workbench?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - 36))
        } else {
            strip.frame = CGRect(x: 0, y: 0, width: 180, height: bounds.height)
            workbench?.frame = CGRect(x: 180, y: 0, width: max(0, bounds.width - 180), height: bounds.height)
        }
    }
}
