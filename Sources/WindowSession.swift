import AppKit

/// Owns a native window and its document selection. Toolbar actions never consult the key window.
final class WindowSession: NSObject, NSWindowDelegate, NSToolbarDelegate {
    let window: NSWindow
    let id = UUID()
    private(set) var transferGeneration: UInt64 = 0
    var onTransfer: ((WindowSession, DocumentSession) -> Void)?
    private var transferClosed = false
    var isTransferLive: Bool { !transferClosed && window.delegate === self }
    private(set) var documents: [DocumentSession] = []
    private(set) var active: DocumentSession?
    var confirmClose: ((DocumentSession) -> Bool)?
    var onClose: ((WindowSession) -> Void)?
    var onRemove: ((WindowSession, DocumentSession) -> Void)?
    private let toolbarTemplate: AppDelegate
    private let defaults: UserDefaults
    let tabStrip = DocumentTabStrip(frame: .zero)
    lazy var tabRoot = DocumentTabRoot(strip: tabStrip)
    var onNewTab: (() -> Void)?
    var onCloseTab: ((DocumentSession) -> Void)?
    private(set) var orientation: DocumentTabOrientation

    init(window: NSWindow, toolbarTemplate: AppDelegate, defaults: UserDefaults = .standard) {
        self.window = window
        self.toolbarTemplate = toolbarTemplate
        self.defaults = defaults
        orientation = DocumentTabOrientation(rawValue: defaults.string(forKey: "openmindflow-tab-orientation") ?? "") ?? .horizontal
        super.init()
        tabStrip.defaults = defaults
        tabStrip.orientation = orientation
        tabStrip.onSelect = { [weak self] id in
            guard let self, let document = self.documents.first(where: { self.tabStrip.id(for: $0) == id }) else { return }
            _ = self.activate(document)
        }
        tabStrip.onClose = { [weak self] id in
            guard let self, let document = self.documents.first(where: { self.tabStrip.id(for: $0) == id }) else { return }
            self.onCloseTab?(document)
        }
        tabStrip.onNewTab = { [weak self] in self?.onNewTab?() }
        tabStrip.onOrientationChange = { [weak self] orientation in self?.setOrientation(orientation) }
        window.contentViewController = tabRoot
        window.delegate = self
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("MindMap.\(UUID().uuidString)"))
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }

    func insert(_ document: DocumentSession, at index: Int? = nil) {
        guard !documents.contains(where: { $0 === document }) else { return }
        documents.insert(document, at: max(0, min(index ?? documents.count, documents.count)))
        transferGeneration &+= 1
        if active == nil { _ = activate(document) }
        refreshTabs()
    }
    @discardableResult func activate(_ document: DocumentSession) -> Bool {
        guard documents.contains(where: { $0 === document }) else { return false }
        if active === document { return true }
        guard active?.commitPendingEditors() ?? true else { return false }
        // Only a successful transition invalidates the outgoing shared-panel target.
        active?.inspector.colorPanelModel = nil
        active?.canvas.invalidateRelationshipColorPanelOwnership()
        active = document
        document.window = window
        tabRoot.display(document.splitController)
        refreshTabs()
        document.onTitleChange?()
        window.makeFirstResponder(document.canvas)
        return true
    }
    func refreshTabs() {
        tabStrip.documents = documents
        tabStrip.selectedID = active.map { tabStrip.id(for: $0) }
    }
    func setOrientation(_ chosen: DocumentTabOrientation) {
        guard chosen != orientation else { return }
        let canvas = active?.canvas
        window.contentView?.layoutSubtreeIfNeeded()
        let oldScreen = canvas.map { window.convertToScreen($0.convert(.zero, to: nil)).origin }
        let frame = window.frame
        orientation = chosen
        defaults.set(chosen.rawValue, forKey: "openmindflow-tab-orientation")
        tabStrip.orientation = chosen
        tabRoot.layoutView.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        if window.frame != frame { window.setFrame(frame, display: false) }
        if let canvas, let oldScreen {
            let newScreen = window.convertToScreen(canvas.convert(.zero, to: nil)).origin
            // The canvas is vertically flipped: negate screen-space Y motion, not map zoom.
            canvas.shiftViewport(by: CGPoint(x: oldScreen.x - newScreen.x,
                                             y: newScreen.y - oldScreen.y))
        }
    }
    private func detachOwnedPanels(from document: DocumentSession) {
        let panel = document.findWindow
        document.findWindow = nil
        document.findField = nil
        document.findStatus = nil
        document.findMatches = []
        document.findIndex = 0
        panel?.orderOut(nil)
        panel?.close()
        document.inspector.colorPanelModel = nil
        document.canvas.invalidateRelationshipColorPanelOwnership()
    }
    /// Array-only ownership change: never clears document state or invokes close callbacks.
    func transferReorder(from source: Int, to destination: Int) {
        let document = documents.remove(at: source)
        documents.insert(document, at: destination)
        transferGeneration &+= 1
        refreshTabs()
    }
    func transferDetach(_ document: DocumentSession) {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return }
        documents.remove(at: index)
        transferGeneration &+= 1
        if active === document {
            active = documents.indices.contains(min(index, documents.count - 1))
                ? documents[min(index, documents.count - 1)] : documents.last
            if let active { tabRoot.display(active.splitController); window.makeFirstResponder(active.canvas) }
            else { tabRoot.display(nil) }
        }
        refreshTabs()
        onTransfer?(self, document)
    }
    func transferAttach(_ document: DocumentSession, at index: Int) {
        documents.insert(document, at: index)
        transferGeneration &+= 1
        active?.inspector.colorPanelModel = nil
        active?.canvas.invalidateRelationshipColorPanelOwnership()
        active = document
        document.window = window
        refreshTabs()
        document.onTitleChange?()
        window.makeFirstResponder(document.canvas)
        onTransfer?(self, document)
    }
    func remove(_ document: DocumentSession) {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return }
        documents.remove(at: index)
        transferGeneration &+= 1
        if active === document {
            active = nil
            if let next = documents.first { _ = activate(next) }
            else { tabRoot.display(nil) }
        }
        refreshTabs()
        detachOwnedPanels(from: document)
        document.window = nil
        onRemove?(self, document)
    }
    func prepareClose(documents closing: [DocumentSession]) -> Bool {
        for document in closing where documents.contains(where: { $0 === document }) {
            guard document.commitPendingEditors(),
                  (confirmClose?(document) ?? true) else { return false }
        }
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { prepareClose(documents: documents) }
    func windowWillClose(_ notification: Notification) {
        transferClosed = true
        transferGeneration &+= 1
        for document in documents {
            detachOwnedPanels(from: document)
            document.window = nil
        }
        active = nil
        onClose?(self)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarTemplate.toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarTemplate.toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let item = toolbarTemplate.toolbar(toolbar, itemForItemIdentifier: identifier,
                                                 willBeInsertedIntoToolbar: flag) else { return nil }
        item.target = self
        return item
    }
    private func commandSession(for sender: Any?) -> DocumentSession? {
        guard let item = sender as? NSToolbarItem, item.target as AnyObject? === self,
              let toolbar = window.toolbar,
              toolbarAllowedItemIdentifiers(toolbar).contains(item.itemIdentifier),
              let document = active, document.window === window,
              documents.contains(where: { $0 === document }) else { return nil }
        return document
    }
    @objc func undoEdit(_ sender: Any?) { if let session = commandSession(for: sender), session.commitPendingEditors() { session.canvas.undo() } }
    @objc func redoEdit(_ sender: Any?) { if let session = commandSession(for: sender), session.commitPendingEditors() { session.canvas.redo() } }
    @objc func newMainNode(_ sender: Any?) { commandSession(for: sender)?.canvas.addMainNode() }
    @objc func newChild(_ sender: Any?) { commandSession(for: sender)?.canvas.addChild() }
    @objc func newSibling(_ sender: Any?) { commandSession(for: sender)?.canvas.addSibling() }
    @objc func foldNode(_ sender: Any?) { commandSession(for: sender)?.canvas.toggleFold() }
    @objc func fitMap(_ sender: Any?) { commandSession(for: sender)?.canvas.fitMapInView() }
    @objc func toggleOutline(_ sender: Any?) { commandSession(for: sender)?.toggleOutline() }
    @objc func toggleStyle(_ sender: Any?) { commandSession(for: sender)?.toggleStyle() }
}
