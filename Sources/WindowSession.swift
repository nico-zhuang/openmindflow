import AppKit

/// Owns a native window and its document selection. Toolbar actions never consult the key window.
final class WindowSession: NSObject, NSWindowDelegate, NSToolbarDelegate {
    let window: NSWindow
    private(set) var documents: [DocumentSession] = []
    private(set) var active: DocumentSession?
    var confirmClose: ((DocumentSession) -> Bool)?
    var onClose: ((WindowSession) -> Void)?
    var onRemove: ((WindowSession, DocumentSession) -> Void)?
    private let toolbarTemplate: AppDelegate

    init(window: NSWindow, toolbarTemplate: AppDelegate) {
        self.window = window
        self.toolbarTemplate = toolbarTemplate
        super.init()
        window.delegate = self
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("MindMap.\(UUID().uuidString)"))
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }

    func insert(_ document: DocumentSession, at index: Int? = nil) {
        guard !documents.contains(where: { $0 === document }) else { return }
        documents.insert(document, at: max(0, min(index ?? documents.count, documents.count)))
        if active == nil { activate(document) }
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
        window.contentViewController = document.splitController
        document.onTitleChange?()
        window.makeFirstResponder(document.canvas)
        return true
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
    func remove(_ document: DocumentSession) {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return }
        documents.remove(at: index)
        if active === document {
            active = nil
            if let next = documents.first { _ = activate(next) }
            else { window.contentViewController = nil }
        }
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
    private var commandSession: DocumentSession? { window.isKeyWindow ? active : nil }
    @objc func undoEdit(_ sender: Any?) { if commandSession?.commitPendingEditors() == true { commandSession?.canvas.undo() } }
    @objc func redoEdit(_ sender: Any?) { if commandSession?.commitPendingEditors() == true { commandSession?.canvas.redo() } }
    @objc func newMainNode(_ sender: Any?) { commandSession?.canvas.addMainNode() }
    @objc func newChild(_ sender: Any?) { commandSession?.canvas.addChild() }
    @objc func newSibling(_ sender: Any?) { commandSession?.canvas.addSibling() }
    @objc func foldNode(_ sender: Any?) { commandSession?.canvas.toggleFold() }
    @objc func fitMap(_ sender: Any?) { commandSession?.canvas.fitMapInView() }
    @objc func toggleOutline(_ sender: Any?) { commandSession?.toggleOutline() }
    @objc func toggleStyle(_ sender: Any?) { commandSession?.toggleStyle() }
}
