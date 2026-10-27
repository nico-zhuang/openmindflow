import AppKit

/// Owns a native window and its document selection. Toolbar actions never consult the key window.
final class WindowSession: NSObject, NSWindowDelegate, NSToolbarDelegate {
    let window: NSWindow
    private(set) var documents: [DocumentSession] = []
    private(set) var active: DocumentSession?
    var confirmClose: ((DocumentSession) -> Bool)?
    var onClose: ((WindowSession) -> Void)?
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
    func activate(_ document: DocumentSession) {
        guard documents.contains(where: { $0 === document }) else { return }
        active = document
        document.window = window
        window.contentViewController = document.splitController
        document.onTitleChange?()
        window.makeFirstResponder(document.canvas)
    }
    func remove(_ document: DocumentSession) {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return }
        documents.remove(at: index)
        if active === document {
            active = nil
            if let next = documents.first { activate(next) }
            else { window.contentViewController = nil }
        }
        document.window = nil
    }
    func prepareClose(documents closing: [DocumentSession]) -> Bool {
        for document in closing where documents.contains(where: { $0 === document }) {
            guard (confirmClose?(document) ?? document.commitPendingEditors()) else { return false }
        }
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { prepareClose(documents: documents) }
    func windowWillClose(_ notification: Notification) {
        for document in documents { document.window = nil }
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
    @objc func undoEdit(_ sender: Any?) { if active?.commitPendingEditors() == true { active?.canvas.undo() } }
    @objc func redoEdit(_ sender: Any?) { if active?.commitPendingEditors() == true { active?.canvas.redo() } }
    @objc func newMainNode(_ sender: Any?) { active?.canvas.addMainNode() }
    @objc func newChild(_ sender: Any?) { active?.canvas.addChild() }
    @objc func newSibling(_ sender: Any?) { active?.canvas.addSibling() }
    @objc func foldNode(_ sender: Any?) { active?.canvas.toggleFold() }
    @objc func fitMap(_ sender: Any?) { active?.canvas.fitMapInView() }
    @objc func toggleOutline(_ sender: Any?) { active?.toggleOutline() }
    @objc func toggleStyle(_ sender: Any?) { active?.toggleStyle() }
}
