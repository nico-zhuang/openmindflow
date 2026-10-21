import AppKit

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

    let outlineView = NSOutlineView()
    private let canvas: MapCanvas
    private var roots: [Row] = []
    private var reloading = false

    init(canvas: MapCanvas) {
        self.canvas = canvas
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("map-title"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 27
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.setAccessibilityLabel("Map outline")
        documentView = outlineView
        hasVerticalScroller = true
        reloadMap()
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view only") }

    func reloadMap() {
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
        let label = NSTextField(labelWithString: row.title.isEmpty ? "New idea" : row.title)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = row.title
        return label
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
        canvas.selectNode(row.id)
        canvas.toggleFold()
        reloadMap()
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        guard !reloading, let row = item as? Row else { return true }
        guard !row.folded else { return true }
        canvas.selectNode(row.id)
        canvas.toggleFold()
        reloadMap()
        return false
    }
}
