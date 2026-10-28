import AppKit

enum DocumentTabOrientation: String { case horizontal, vertical }

/// The tab control is outside each document's three-pane workbench.
final class DocumentTabStrip: NSView {
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
        for row in rows { row.view.removeFromSuperview() }
        rows.removeAll()
        let live = Set(documents.map(ObjectIdentifier.init))
        identifiers = identifiers.filter { live.contains($0.key) }
        for document in documents {
            let id = id(for: document)
            let row = NSView(frame: .zero)
            let name = document.fileURL?.lastPathComponent ?? L10n.text("Untitled", defaults: defaults)
            let title = DragTabButton(title: name + (document.dirty ? " •" : ""), target: self,
                                     action: #selector(selectTab(_:)))
            title.strip = self
            title.bezelStyle = .recessed
            title.setAccessibilityLabel(name + (document.dirty ? ", " + L10n.text("Modified", defaults: defaults) : ""))
            title.setAccessibilityRole(.radioButton)
            title.state = selectedID == id ? .on : .off
            row.addSubview(title)
            let close = NSButton(title: "×", target: self, action: #selector(closeTab(_:)))
            close.bezelStyle = .recessed
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
            close.frame = CGRect(x: row.view.bounds.width - 28, y: 3, width: 24, height: row.view.bounds.height - 6)
        }
        addButton.frame = horizontal ? CGRect(x: CGFloat(rows.count) * extent + 4, y: 3, width: 30, height: bounds.height - 6)
                                     : CGRect(x: 4, y: CGFloat(rows.count) * extent + 3, width: 30, height: 29)
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
        guard draggingToken == token, let signal = releaseSignal else { return }
        signal.disarm(token: token)
        if DocumentDragApplication.activeReleaseSignal === signal {
            DocumentDragApplication.activeReleaseSignal = nil
        }
        releaseSignal = nil
        draggingToken = nil
        for owner in transfer?.eligibleWindows?() ?? [] { owner.tabStrip.cancelInsertionPreview() }
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
        guard draggingToken == nil, releaseSignal == nil,
              DocumentDragApplication.activeReleaseSignal == nil,
              window?.isVisible == true, let owner = liveOwner, let transfer,
              let document = liveDocument(for: button, controlIndex: 0),
              let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { return false }
        let token = transfer.begin(document: document, source: owner)
        let item = NSPasteboardItem()
        guard item.setData(Data(token.uuidString.utf8), forType: DocumentTabTransfer.pasteboardType) else {
            transfer.cancel(token: token); return false
        }
        button.cacheDisplay(in: button.bounds, to: bitmap)
        let image = NSImage(size: button.bounds.size)
        image.addRepresentation(bitmap)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(button.convert(button.bounds, to: self), contents: image)
        let signal = DragReleaseSignal()
        draggingToken = token
        releaseSignal = signal
        signal.arm(token: token, after: event.timestamp, sourceWindowNumber: owner.window.windowNumber)
        DocumentDragApplication.activeReleaseSignal = signal
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
        defer {
            signal.disarm(token: token)
            if DocumentDragApplication.activeReleaseSignal === signal {
                DocumentDragApplication.activeReleaseSignal = nil
            }
            releaseSignal = nil
            draggingToken = nil
            transfer?.cancel(token: token)
            for owner in transfer?.eligibleWindows?() ?? [] { owner.tabStrip.cancelInsertionPreview() }
        }
        _ = transfer?.finish(token: token, locationOnScreen: screenPoint, operation: operation, signal: signal)
    }
}

/// Native button actions remain keyboard/AX-clickable; only pointer motion enters AppKit drag.
private final class DragTabButton: NSButton {
    weak var strip: DocumentTabStrip?
    override func mouseDown(with event: NSEvent) {
        let origin = convert(event.locationInWindow, from: nil)
        isHighlighted = true
        defer { isHighlighted = false }
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                                         until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .keyDown { return } // Escape and uncertain key interruptions do not start a drag.
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
