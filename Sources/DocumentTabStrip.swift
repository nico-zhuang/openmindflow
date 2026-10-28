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
    private var identifiers: [ObjectIdentifier: UUID] = [:]
    private var rows: [(document: DocumentSession, view: NSView)] = []
    private let addButton = NSButton(title: "+", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addButton.bezelStyle = .texturedRounded
        addButton.target = self
        addButton.action = #selector(addTab(_:))
        addSubview(addButton)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view only") }
    override var isFlipped: Bool { true }
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
            let title = NSButton(title: name + (document.dirty ? " •" : ""), target: self,
                                 action: #selector(selectTab(_:)))
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
        return max(0, min(documents.count, Int(max(0, coordinate) / (orientation == .horizontal ? 154 : 35) + 0.5)))
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
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for choice in [DocumentTabOrientation.horizontal, .vertical] {
            let item = menu.addItem(withTitle: L10n.text(choice == .horizontal ? "Horizontal Tabs" : "Vertical Tabs", defaults: defaults),
                                    action: #selector(selectOrientation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = choice == orientation ? .on : .off
        }
        return menu
    }
    @objc private func selectOrientation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let value = DocumentTabOrientation(rawValue: raw) else { return }
        onOrientationChange(value)
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
        if let workbench { workbench.view.removeFromSuperview(); workbench.removeFromParent() }
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
