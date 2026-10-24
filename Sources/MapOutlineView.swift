import AppKit

final class KeyboardOutlineView: NSOutlineView {
    var contextMenuForRow: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuForRow?(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func keyDown(with event: NSEvent) {
        if [UInt16(36), 76].contains(event.keyCode), selectedRow >= 0,
           event.modifierFlags.intersection([.shift, .option, .command, .control]).isEmpty,
           let doubleAction, NSApp.sendAction(doubleAction, to: target, from: self) { return }
        super.keyDown(with: event)
    }
}

final class MapOutlineView: NSScrollView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private final class Row: NSObject {
        let id: UUID
        let title: String
        let folded: Bool
        let children: [Row]

        init(_ node: MapNode) {
            id = node.id
            title = node.title
            folded = node.folded
            children = node.children.map(Row.init)
        }
    }

    let outlineView = KeyboardOutlineView()
    private let canvas: MapCanvas
    private let localizationDefaults: UserDefaults
    private var roots: [Row] = []
    private var reloading = false
    private var disclosureInProgress = false
    private var pendingReload = false

    init(canvas: MapCanvas, defaults: UserDefaults = .standard) {
        self.canvas = canvas
        localizationDefaults = defaults
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("map-title"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 27
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(editSelectedNode(_:))
        outlineView.contextMenuForRow = { [weak self] row in
            guard let self else { return nil }
            guard row >= 0, let item = self.outlineView.item(atRow: row) as? Row else {
                return self.canvas.contextMenu(for: nil)
            }
            self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            return self.canvas.contextMenu(for: item.id)
        }
        outlineView.setAccessibilityLabel(L10n.text("Map outline", defaults: localizationDefaults))
        documentView = outlineView
        hasVerticalScroller = true
        reloadMap()
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view only") }

    func localize() {
        outlineView.setAccessibilityLabel(L10n.text("Map outline", defaults: localizationDefaults))
        reloadMap()
    }

    func reloadMap() {
        if disclosureInProgress {
            guard !pendingReload else { return }
            pendingReload = true
            DispatchQueue.main.async { [weak self] in
                self?.pendingReload = false
                self?.reloadMap() // AppKit has finished using the disclosure's old Row.
            }
            return
        }
        reloading = true
        defer { reloading = false }
        roots = canvas.model.roots.map(Row.init)
        outlineView.reloadData()
        func reveal(_ rows: [Row]) {
            for row in rows where !row.folded && !row.children.isEmpty {
                outlineView.expandItem(row)
                reveal(row.children)
            }
        }
        reveal(roots)
        syncSelection()
    }

    func syncSelection() {
        let row = (0..<outlineView.numberOfRows).first {
            (outlineView.item(atRow: $0) as? Row)?.id == canvas.model.selected
        }
        reloading = true
        defer { reloading = false }
        if let row { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else { outlineView.deselectAll(nil) }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Row)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? Row)?.children ?? roots)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !(item as! Row).children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let row = item as! Row
        let label = NSTextField(labelWithString: row.title.isEmpty
            ? L10n.text("New idea", defaults: localizationDefaults) : row.title)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = row.title
        return label
    }

    @objc private func editSelectedNode(_ sender: NSOutlineView) {
        guard sender.selectedRow >= 0, let row = sender.item(atRow: sender.selectedRow) as? Row else { return }
        canvas.selectAndEdit(row.id)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, outlineView.selectedRow >= 0,
              let row = outlineView.item(atRow: outlineView.selectedRow) as? Row else { return }
        let id = row.id
        canvas.selectNode(id) // Commits the previous canvas editor before changing selected UUID.
        if window != nil { window?.makeFirstResponder(outlineView) }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard !reloading, let row = item as? Row else { return true }
        guard row.folded else { return true }
        disclosureInProgress = true
        defer { disclosureInProgress = false }
        canvas.selectNode(row.id)
        canvas.toggleFold()
        reloadMap()
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        guard !reloading, let row = item as? Row else { return true }
        guard !row.folded else { return true }
        disclosureInProgress = true
        defer { disclosureInProgress = false }
        canvas.selectNode(row.id)
        canvas.toggleFold()
        reloadMap()
        return false
    }
}
