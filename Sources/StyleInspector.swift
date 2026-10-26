import AppKit

// The preview is painted at the card's current width rather than letting NSButton's
// imageAbove cell compress a fixed-size image to make room for the title.
private final class ThemeCardButton: NSButton {
    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 4)
        image?.size = NSSize(width: width, height: width * 156 / 392)
    }

    override func draw(_ dirtyRect: NSRect) {
        let width = max(0, bounds.width - 4)
        let imageRect = NSRect(x: 2, y: bounds.height - 2 - width * 156 / 392,
                               width: width, height: width * 156 / 392)
        image?.draw(in: imageRect)
        let border = NSBezierPath(roundedRect: imageRect.insetBy(dx: 0.75, dy: 0.75),
                                  xRadius: 6, yRadius: 6)
        (state == .on ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        border.lineWidth = state == .on ? 2.5 : 1
        border.stroke()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor
        ]
        let label = title as NSString
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                               y: max(0, imageRect.minY - 18)), withAttributes: attributes)
    }
}

final class StyleInspector: NSView, NSTextViewDelegate {
    private let canvas: MapCanvas
    private let defaults: UserDefaults
    private var labels: [String: NSTextField] = [:]
    private static let widths: [(String, CGFloat)] = [("Hairline", 0.75), ("Thin", 1.5),
                                                       ("Medium", 3), ("Bold", 5), ("Heavy", 8)]
    static let colors = [("Teal", "#14B8A6FF"), ("Blue", "#3478F6FF"),
                                 ("Coral", "#F97373FF"), ("Gold", "#EAB308FF"),
                                 ("Gray", "#8B95A5FF")]
    let familyPopup = NSPopUpButton()
    let fontPreview = NSTextField(labelWithString: "Aa 字")
    let fontSizeField = NSTextField()
    let fontSizeStepper = NSStepper()
    let alignmentControl = NSSegmentedControl(labels: ["", "", "", ""], trackingMode: .selectOne, target: nil, action: nil)
    let colorPopup = NSPopUpButton()
    let colorState = NSTextField(labelWithString: "")
    let strokeWidthPopup = NSPopUpButton()
    let strokeStylePopup = NSPopUpButton()
    let tabs = NSSegmentedControl(labels: ["", "", ""], trackingMode: .selectOne, target: nil, action: nil)
    let styleScroll = NSScrollView()
    let notesScroll = NSScrollView()
    let noteTextView = NSTextView()
    let noteStatus = NSTextField(labelWithString: "")
    let backgroundPopup = NSPopUpButton()
    let rootShapePopup = NSPopUpButton()
    let rootFillPopup = NSPopUpButton()
    let rootWidthPopup = NSPopUpButton()
    private let themeScroll = NSScrollView()
    private static let featuredThemes: [InspectorTheme] = [.tropical, .teal, .slate, .coffee]
    private(set) var themeButtons: [NSButton] = []
    private var noteNodeID: UUID?
    private var loadedNote = ""
    private var refreshing = false
    weak var colorPanelModel: MapModel?

    override var intrinsicContentSize: NSSize { NSSize(width: 280, height: NSView.noIntrinsicMetric) }

    init(canvas: MapCanvas, defaults: UserDefaults = .standard) {
        self.canvas = canvas
        self.defaults = defaults
        super.init(frame: .zero)
        canvas.onBeforeCommit = { [weak self] in self?.commitNoteEditing() ?? true }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        tabs.target = self
        tabs.action = #selector(selectPage(_:))
        tabs.selectedSegment = 0
        tabs.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabs)
        for page in [styleScroll, notesScroll, themeScroll] {
            page.translatesAutoresizingMaskIntoConstraints = false
            page.hasVerticalScroller = true
            page.autohidesScrollers = true
            addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: leadingAnchor),
                page.trailingAnchor.constraint(equalTo: trailingAnchor),
                page.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
                page.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            tabs.centerXAnchor.constraint(equalTo: centerXAnchor),
            tabs.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
        let styleDocument = NSView()
        styleDocument.translatesAutoresizingMaskIntoConstraints = false
        styleScroll.documentView = styleDocument
        styleDocument.addSubview(stack)
        NSLayoutConstraint.activate([
            styleDocument.widthAnchor.constraint(equalTo: styleScroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: styleDocument.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: styleDocument.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: styleDocument.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: styleDocument.bottomAnchor, constant: -12)
        ])
        notesScroll.documentView = noteTextView
        notesScroll.contentInsets.bottom = 24
        noteTextView.isRichText = false
        noteTextView.isAutomaticQuoteSubstitutionEnabled = false
        noteTextView.isAutomaticTextReplacementEnabled = false
        noteTextView.isVerticallyResizable = true
        noteTextView.textContainer?.widthTracksTextView = true
        noteTextView.delegate = self
        noteStatus.translatesAutoresizingMaskIntoConstraints = false
        addSubview(noteStatus)
        NSLayoutConstraint.activate([
            noteStatus.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            noteStatus.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            noteStatus.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
        noteStatus.setAccessibilityRole(.staticText)
        let themes = NSStackView()
        themes.orientation = .vertical
        themes.spacing = 12
        themes.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        themes.translatesAutoresizingMaskIntoConstraints = false
        let themeDocument = NSView()
        themeDocument.translatesAutoresizingMaskIntoConstraints = false
        themeScroll.documentView = themeDocument
        themeDocument.addSubview(themes)
        NSLayoutConstraint.activate([
            themeDocument.widthAnchor.constraint(equalTo: themeScroll.contentView.widthAnchor),
            themes.leadingAnchor.constraint(equalTo: themeDocument.leadingAnchor),
            themes.trailingAnchor.constraint(equalTo: themeDocument.trailingAnchor),
            themes.topAnchor.constraint(equalTo: themeDocument.topAnchor),
            themes.bottomAnchor.constraint(equalTo: themeDocument.bottomAnchor)
        ])
        for (index, theme) in Self.featuredThemes.enumerated() {
            let button = ThemeCardButton(title: theme.rawValue.capitalized, target: self,
                                         action: #selector(changeTheme(_:)))
            button.tag = index
            button.image = preview(for: theme)
            button.setAccessibilityLabel(theme.rawValue.capitalized)
            button.translatesAutoresizingMaskIntoConstraints = false
            themes.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalTo: themes.widthAnchor, constant: -24),
                NSLayoutConstraint(item: button, attribute: .height, relatedBy: .equal,
                                   toItem: button, attribute: .width, multiplier: 156 / 392,
                                   constant: 18)
            ])
            themeButtons.append(button)
        }
        styleScroll.isHidden = false
        notesScroll.isHidden = true
        themeScroll.isHidden = true
        func section(_ title: String) {
            let label = NSTextField(labelWithString: title)
            labels[title] = label
            label.font = .boldSystemFont(ofSize: 11)
            stack.addArrangedSubview(label)
        }
        func row(_ title: String, _ control: NSView) {
            let label = NSTextField(labelWithString: title)
            labels[title] = label
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            let line = NSStackView(views: [label, control])
            line.orientation = title == "Canvas Background" ? .vertical : .horizontal
            line.alignment = title == "Canvas Background" ? .leading : .centerY
            line.spacing = 8
            stack.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        section("FONT")
        familyPopup.addItem(withTitle: "Mixed")
        familyPopup.addItem(withTitle: "Unavailable")
        for family in NSFontManager.shared.availableFontFamilies.sorted() {
            let item = familyPopup.menu!.addItem(withTitle: family, action: nil, keyEquivalent: "")
            let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 14)
                ?? .systemFont(ofSize: 14)
            item.attributedTitle = NSAttributedString(string: family, attributes: [.font: font])
            item.representedObject = font.fontName
        }
        familyPopup.setAccessibilityLabel("Font family")
        familyPopup.target = self
        familyPopup.action = #selector(changeFontFamily(_:))
        row("Family", familyPopup)
        fontPreview.setAccessibilityLabel("Font preview")
        row("Preview", fontPreview)
        fontSizeField.setAccessibilityLabel("Font size")
        fontSizeField.target = self
        fontSizeField.action = #selector(changeFontSize(_:))
        fontSizeStepper.minValue = 6
        fontSizeStepper.maxValue = 240
        fontSizeStepper.increment = 1
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(changeFontSize(_:))
        let sizeControls = NSStackView(views: [fontSizeField, fontSizeStepper])
        sizeControls.spacing = 6
        row("Size", sizeControls)
        alignmentControl.setAccessibilityLabel("Paragraph alignment")
        for (index, pair) in [("Left", "text.alignleft"), ("Center", "text.aligncenter"),
                              ("Right", "text.alignright"), ("Justify", "text.justify")].enumerated() {
            alignmentControl.setImage(NSImage(systemSymbolName: pair.1, accessibilityDescription: pair.0), forSegment: index)
            alignmentControl.setToolTip(pair.0, forSegment: index)
        }
        alignmentControl.target = self
        alignmentControl.action = #selector(changeAlignment(_:))
        row("Align", alignmentControl)
        section("CONNECTION")
        colorPopup.addItems(withTitles: ["Mixed", "Default", "Custom"])
        for item in colorPopup.itemArray { item.representedObject = item.title }
        for (title, hex) in Self.colors {
            let item = colorPopup.menu!.addItem(withTitle: title, action: nil, keyEquivalent: "")
            item.representedObject = title
            if let color = Self.color(hex) {
                item.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                    color.setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                    return true
                }
            }
        }
        colorPopup.addItem(withTitle: "More…")
        colorPopup.item(withTitle: "More…")?.representedObject = "More…"
        colorPopup.setAccessibilityLabel("Connection color")
        colorPopup.target = self
        colorPopup.action = #selector(changeColorSelection(_:))
        colorPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        row("Color", colorPopup)
        strokeWidthPopup.addItems(withTitles: ["Default", "Mixed", "Custom"] + Self.widths.map(\.0))
        for item in strokeWidthPopup.itemArray { item.representedObject = item.title }
        strokeWidthPopup.setAccessibilityLabel("Connection width")
        strokeWidthPopup.target = self
        strokeWidthPopup.action = #selector(changeStrokeWidth(_:))
        row("Width", strokeWidthPopup)
        strokeStylePopup.addItems(withTitles: ["Default", "Solid", "Dashed", "Mixed"])
        for item in strokeStylePopup.itemArray { item.representedObject = item.title }
        strokeStylePopup.setAccessibilityLabel("Connection line style")
        strokeStylePopup.target = self
        strokeStylePopup.action = #selector(changeStrokeStyle(_:))
        row("Line", strokeStylePopup)
        section("ROOT")
        rootShapePopup.addItems(withTitles: ["Rounded", "Rectangle"])
        for item in rootShapePopup.itemArray { item.representedObject = item.title }
        rootShapePopup.target = self
        rootShapePopup.action = #selector(changeRootShape(_:))
        row("Shape", rootShapePopup)
        rootFillPopup.addItems(withTitles: ["Default"] + Self.colors.map(\.0) + ["More…"])
        for item in rootFillPopup.itemArray {
            item.representedObject = item.title
            item.image = colorPopup.item(withTitle: item.title)?.image
        }
        rootFillPopup.target = self
        rootFillPopup.action = #selector(changeRootFill(_:))
        row("Fill", rootFillPopup)
        rootWidthPopup.addItems(withTitles: ["Auto", "Narrow (170 pt)", "Medium (240 pt)",
                                             "Wide (320 pt)", "Extra Wide (480 pt)"])
        for item in rootWidthPopup.itemArray { item.representedObject = item.title }
        rootWidthPopup.target = self
        rootWidthPopup.action = #selector(changeRootWidth(_:))
        row("Fixed width", rootWidthPopup)
        section("CANVAS")
        backgroundPopup.addItems(withTitles: ["Follow System", "Light", "Dark", "More…"])
        for item in backgroundPopup.itemArray { item.representedObject = item.title }
        backgroundPopup.target = self
        backgroundPopup.action = #selector(changeCanvasBackground(_:))
        row("Canvas Background", backgroundPopup)
        localize()
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view only") }

    func localize() {
        func text(_ key: String) -> String { L10n.text(key, defaults: defaults) }
        for (key, label) in labels { label.stringValue = text(key) }
        familyPopup.item(at: 0)?.title = text("Mixed")
        familyPopup.item(at: 1)?.title = text("Unavailable")
        for popup in [colorPopup, strokeWidthPopup, strokeStylePopup, rootShapePopup,
                      rootFillPopup, rootWidthPopup, backgroundPopup] {
            for item in popup.itemArray {
                if let key = item.representedObject as? String { item.title = text(key) }
            }
        }
        familyPopup.setAccessibilityLabel(text("Font family"))
        fontPreview.setAccessibilityLabel(text("Font preview"))
        fontSizeField.setAccessibilityLabel(text("Font size"))
        fontSizeStepper.setAccessibilityLabel(text("Font size"))
        alignmentControl.setAccessibilityLabel(text("Paragraph alignment"))
        for (index, pair) in [("Left", "text.alignleft"), ("Center", "text.aligncenter"),
                              ("Right", "text.alignright"), ("Justify", "text.justify")].enumerated() {
            alignmentControl.setImage(NSImage(systemSymbolName: pair.1, accessibilityDescription: text(pair.0)),
                                      forSegment: index)
            alignmentControl.setToolTip(text(pair.0), forSegment: index)
        }
        colorPopup.setAccessibilityLabel(text("Connection color"))
        strokeWidthPopup.setAccessibilityLabel(text("Connection width"))
        strokeStylePopup.setAccessibilityLabel(text("Connection line style"))
        rootShapePopup.setAccessibilityLabel(text("Root shape"))
        rootFillPopup.setAccessibilityLabel(text("Root fill"))
        rootWidthPopup.setAccessibilityLabel(text("Fixed width"))
        backgroundPopup.setAccessibilityLabel(text("Canvas Background"))
        noteTextView.setAccessibilityLabel(text("Notes"))
        noteStatus.setAccessibilityLabel(text("Note status"))
        for (index, pair) in [("paintbrush", "Style"), ("note.text", "Notes"),
                              ("paintpalette", "Themes")].enumerated() {
            tabs.setImage(NSImage(systemSymbolName: pair.0, accessibilityDescription: text(pair.1)), forSegment: index)
            tabs.setToolTip(text(pair.1), forSegment: index)
        }
        for (button, theme) in zip(themeButtons, Self.featuredThemes) {
            button.title = text(theme.rawValue.capitalized)
            button.setAccessibilityLabel(button.title)
        }
        refresh()
    }

    static func color(_ hex: String) -> NSColor? {
        guard hex.count == 9, hex.first == "#",
              let red = UInt8(hex.dropFirst().prefix(2), radix: 16),
              let green = UInt8(hex.dropFirst(3).prefix(2), radix: 16),
              let blue = UInt8(hex.dropFirst(5).prefix(2), radix: 16),
              let alpha = UInt8(hex.dropFirst(7).prefix(2), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                       blue: CGFloat(blue) / 255, alpha: CGFloat(alpha) / 255)
    }

    private func selectedNodes() -> [(MapNode, Bool)] {
        let selected = canvas.model.selectedIDs
        func visit(_ nodes: [MapNode], isRoot: Bool) -> [(MapNode, Bool)] {
            nodes.flatMap { node in
                (selected.contains(node.id) ? [(node, isRoot)] : []) + visit(node.children, isRoot: false)
            }
        }
        return visit(canvas.model.roots, isRoot: true)
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        guard commitNoteEditing() else {
            if let noteNodeID, canvas.model.selected != noteNodeID {
                canvas.model.selected = noteNodeID
                canvas.needsDisplay = true
            }
            return
        }
        let relation = canvas.model.relationships.first { $0.id == canvas.selectedRelationshipID }
        tabs.setEnabled(relation == nil, forSegment: 1)
        if relation != nil && tabs.selectedSegment == 1 { tabs.selectedSegment = 0; showPage() }
        let currentID = relation == nil && canvas.model.selectedIDs.count == 1 ? canvas.model.selected : nil
        if noteNodeID != currentID || noteTextView.string != loadedNote ||
           (currentID.flatMap { node($0, in: canvas.model.roots)?.note } ?? "") != loadedNote {
            loadNote(for: currentID)
        }
        rootShapePopup.isEnabled = relation == nil && selectedNodes().count == 1 && selectedNodes().first?.1 == true
        rootFillPopup.isEnabled = rootShapePopup.isEnabled
        rootWidthPopup.isEnabled = rootShapePopup.isEnabled
        let root = selectedNodes().first?.0
        rootShapePopup.selectItem(withTitle: L10n.text(root?.rootShape == "rectangle" ? "Rectangle" : "Rounded", defaults: defaults))
        rootFillPopup.selectItem(withTitle: L10n.text(root?.rootFillColor.flatMap { saved in
            Self.colors.first(where: { $0.1 == saved.uppercased() })?.0
        } ?? (root?.rootFillColor == nil ? "Default" : "More…"), defaults: defaults))
        let widthIndex = root?.width.flatMap { MapNode.widthPresets.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        rootWidthPopup.selectItem(at: widthIndex)
        let followsTheme = canvas.model.canvasColor == nil &&
            canvas.model.theme.flatMap(InspectorTheme.init(rawValue:))?.canvasBackground != nil
        backgroundPopup.item(at: 0)?.title = L10n.text(followsTheme ? "Follow Theme" : "Follow System",
                                                        defaults: defaults)
        backgroundPopup.selectItem(withTitle: L10n.text(canvas.model.canvasColor == nil ?
            (followsTheme ? "Follow Theme" : "Follow System") :
            canvas.model.canvasColor == "#FFFFFFFF" ? "Light" : canvas.model.canvasColor == "#141414FF" ? "Dark" : "More…", defaults: defaults))
        for (button, theme) in zip(themeButtons, Self.featuredThemes) {
            button.state = canvas.model.theme == theme.rawValue ? .on : .off
        }
        func text(_ key: String) -> String { L10n.text(key, defaults: defaults) }
        let nodes = selectedNodes()
        for control: NSControl in [familyPopup, fontSizeField, fontSizeStepper, alignmentControl,
                                   strokeWidthPopup, strokeStylePopup] {
            control.isEnabled = relation == nil && !nodes.isEmpty
        }
        colorPopup.isEnabled = relation != nil || !nodes.isEmpty
        if let relation {
            familyPopup.selectItem(withTitle: text("Mixed"))
            fontPreview.stringValue = text("No selection")
            fontSizeField.stringValue = ""
            alignmentControl.selectedSegment = -1
            strokeWidthPopup.selectItem(withTitle: text("Default"))
            strokeStylePopup.selectItem(withTitle: text("Default"))
            colorState.stringValue = relation.color == nil ? text("Default") : ""
            colorPopup.selectItem(withTitle: text(relation.color.map { saved in
                Self.colors.first(where: { $0.1 == saved.uppercased() })?.0 ?? "Custom"
            } ?? "Default"))
            return
        }
        guard let first = nodes.first else {
            familyPopup.selectItem(withTitle: text("Mixed"))
            fontPreview.stringValue = text("No selection")
            fontSizeField.stringValue = ""
            strokeWidthPopup.selectItem(withTitle: text("Default"))
            colorPopup.selectItem(withTitle: text("Default"))
            alignmentControl.selectedSegment = -1
            colorState.stringValue = text("No selection")
            strokeStylePopup.selectItem(withTitle: text("Default"))
            return
        }
        func family(_ entry: (MapNode, Bool)) -> String {
            entry.0.fontFamily ?? canvas.nativePresentation[entry.0.id]?.font?.family
                ?? (entry.1 ? canvas.embeddedTheme?.mainNodes.first?.font?.family
                             : canvas.embeddedTheme?.baseSubnode?.font?.family)
                ?? "STSongti-SC-Regular"
        }
        func size(_ entry: (MapNode, Bool)) -> Double {
            entry.0.fontSize ?? canvas.nativePresentation[entry.0.id]?.font?.pointSize
                ?? (entry.1 ? canvas.embeddedTheme?.mainNodes.first?.font?.pointSize
                             : canvas.embeddedTheme?.baseSubnode?.font?.pointSize)
                ?? (entry.1 ? 24 : 20)
        }
        let families = nodes.map(family), sizes = nodes.map(size)
        let sameFamily = families.allSatisfy { $0 == families[0] }
        if sameFamily {
            let display = NSFont(name: families[0], size: 16)?.familyName ?? families[0]
            if familyPopup.item(withTitle: display) != nil { familyPopup.selectItem(withTitle: display) }
            else {
                let unavailable = familyPopup.item(at: 1)!
                unavailable.title = String(format: text("Unavailable: %@"), families[0])
                familyPopup.select(unavailable)
            }
            fontPreview.stringValue = "Aa 字"
            fontPreview.font = NSFont(name: families[0], size: 18) ?? .systemFont(ofSize: 18)
        } else {
            familyPopup.selectItem(withTitle: text("Mixed"))
            fontPreview.stringValue = text("Mixed")
            fontPreview.font = .systemFont(ofSize: 13)
        }
        let sameSize = sizes.allSatisfy { $0 == sizes[0] }
        fontSizeField.stringValue = sameSize ? String(format: "%g", sizes[0]) : ""
        fontSizeField.placeholderString = text(sameSize ? "Size" : "Mixed")
        fontSizeStepper.doubleValue = sizes[0]
        let alignment = first.0.textAlignment
        let sameAlignment = nodes.allSatisfy { $0.0.textAlignment == alignment }
        alignmentControl.selectedSegment = sameAlignment
            ? ["left", "center", "right", "justify"].firstIndex(of: alignment ?? "") ?? -1 : -1
        alignmentControl.toolTip = text(sameAlignment ? (alignment?.capitalized ?? "Default") : "Mixed")
        let color = first.0.branchStrokeColor
        let sameColor = nodes.allSatisfy { $0.0.branchStrokeColor == color }
        colorState.stringValue = sameColor ? (color == nil ? text("Default") : "") : text("Mixed")
        colorPopup.selectItem(withTitle: text(sameColor
            ? color.map { saved in Self.colors.first(where: { $0.1 == saved.uppercased() })?.0 ?? "Custom" }
                ?? "Default" : "Mixed"))
        let width = first.0.branchStrokeWidth
        let sameWidth = nodes.allSatisfy { $0.0.branchStrokeWidth == width }
        strokeWidthPopup.selectItem(withTitle: text(sameWidth
            ? width.map { value in Self.widths.first(where: { $0.1 == value })?.0 ?? "Custom" }
                ?? "Default" : "Mixed"))
        let style = first.0.strokeStyle
        strokeStylePopup.selectItem(withTitle: text(nodes.allSatisfy({ $0.0.strokeStyle == style })
                                        ? style.map { $0.capitalized } ?? "Default" : "Mixed"))
    }

    private func node(_ id: UUID, in nodes: [MapNode]) -> MapNode? {
        for node in nodes {
            if node.id == id { return node }
            if let child = self.node(id, in: node.children) { return child }
        }
        return nil
    }

    private func loadNote(for id: UUID?) {
        noteNodeID = id
        loadedNote = id.flatMap { node($0, in: canvas.model.roots)?.note } ?? ""
        noteTextView.string = loadedNote
        noteTextView.isEditable = id != nil
        noteStatus.stringValue = ""
    }

    @discardableResult
    func commitNoteEditing() -> Bool {
        guard let id = noteNodeID else { return true }
        let value = noteTextView.string
        guard value != loadedNote else { return true }
        guard value.utf8.count <= 65_536, canvas.model.setNote(value, for: id) else {
            noteStatus.stringValue = L10n.text("Note exceeds 64 KiB or document limit", defaults: defaults)
            noteStatus.setAccessibilityValue(noteStatus.stringValue)
            window?.makeFirstResponder(noteTextView)
            return false
        }
        loadedNote = value
        noteStatus.stringValue = ""
        canvas.needsDisplay = true
        canvas.onChange?()
        return true
    }

    @discardableResult
    func selectNotes(for id: UUID) -> Bool {
        guard canvas.selectedRelationshipID == nil, canvas.commitEditing(), commitNoteEditing(),
              canvas.model.selectedIDs == [id] else { return false }
        loadNote(for: id)
        tabs.selectedSegment = 1
        showPage()
        window?.makeFirstResponder(noteTextView)
        return true
    }

    @objc private func selectPage(_ sender: NSSegmentedControl) {
        guard canvas.commitEditing(), commitNoteEditing() else {
            sender.selectedSegment = notesScroll.isHidden ? (themeScroll.isHidden ? 0 : 2) : 1
            return
        }
        showPage()
    }

    private func showPage() {
        styleScroll.isHidden = tabs.selectedSegment != 0
        notesScroll.isHidden = tabs.selectedSegment != 1
        themeScroll.isHidden = tabs.selectedSegment != 2
        noteStatus.isHidden = tabs.selectedSegment != 1
    }

    private func ready() -> Bool { canvas.commitEditing() && commitNoteEditing() }

    @objc func changeCanvasBackground(_ sender: Any?) {
        guard ready(), let choice = backgroundPopup.selectedItem?.representedObject as? String else { refresh(); return }
        if choice == "More…" {
            colorPanelModel = canvas.model
            let panel = NSColorPanel.shared
            panel.setTarget(self)
            panel.setAction(#selector(changeCanvasPanelColor(_:)))
            panel.makeKeyAndOrderFront(nil)
        } else {
            changed(canvas.model.setCanvasColor(["Light": "#FFFFFFFF", "Dark": "#141414FF"][choice]))
        }
    }
    @objc private func changeCanvasPanelColor(_ sender: NSColorPanel) {
        guard colorPanelModel === canvas.model, ready(),
              let color = sender.color.usingColorSpace(.deviceRGB) else { return }
        changed(canvas.model.setCanvasColor(Self.hex(color)))
    }
    static func hex(_ color: NSColor) -> String {
        "#" + [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            .map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
    }
    @objc func changeRootShape(_ sender: Any?) {
        guard ready() else { return }
        changed(canvas.model.setRootShape(rootShapePopup.selectedItem?.representedObject as? String == "Rectangle" ? "rectangle" : "rounded"))
    }
    @objc private func changeRootFill(_ sender: Any?) {
        guard ready() else { return }
        if rootFillPopup.selectedItem?.representedObject as? String == "More…" {
            colorPanelModel = canvas.model
            let panel = NSColorPanel.shared
            panel.setTarget(self)
            panel.setAction(#selector(changeRootPanelColor(_:)))
            panel.makeKeyAndOrderFront(nil)
        } else if let choice = rootFillPopup.selectedItem?.representedObject as? String {
            changed(canvas.model.setRootFillColor(Self.colors.first(where: { $0.0 == choice })?.1))
        }
    }
    @objc private func changeRootPanelColor(_ sender: NSColorPanel) {
        guard colorPanelModel === canvas.model, ready(),
              let color = sender.color.usingColorSpace(.deviceRGB) else { return }
        changed(canvas.model.setRootFillColor(Self.hex(color)))
    }
    @objc func changeRootWidth(_ sender: Any?) {
        guard ready() else { return }
        let index = rootWidthPopup.indexOfSelectedItem
        changed(canvas.model.setWidth(index == 0 ? nil : MapNode.widthPresets[index - 1]))
    }
    @objc private func changeTheme(_ sender: NSButton) {
        guard ready() else { return }
        changed(canvas.model.setTheme(Self.featuredThemes[sender.tag].rawValue))
    }
    private func preview(for theme: InspectorTheme) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 392, pixelsHigh: 156,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        (Self.color(theme.canvasBackground ?? "#FFFFFFFF") ?? .white).setFill()
        NSRect(x: 0, y: 0, width: 392, height: 156).fill()
        let root = NSBezierPath(roundedRect: NSRect(x: 115, y: 55, width: 150, height: 46),
                                xRadius: 7, yRadius: 7)
        Self.color(theme.rootFill)?.setFill()
        root.fill()
        let rootInk = Self.color(theme.rootTitleColor ?? "#252D2CFF") ?? .black
        ("Central" as NSString).draw(at: NSPoint(x: 158, y: 70), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: rootInk
        ])
        for index in 0..<3 {
            let y = CGFloat(29 + index * 49)
            let stroke = Self.color(theme.branchColors[index]) ?? .systemTeal
            stroke.setStroke()
            for (start, end, controlX) in [(115.0, 19.0, 68.0), (265.0, 373.0, 313.0)] {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: start, y: 78))
                line.curve(to: NSPoint(x: end, y: y),
                           controlPoint1: NSPoint(x: controlX, y: 78),
                           controlPoint2: NSPoint(x: controlX, y: y))
                line.lineWidth = 4
                line.stroke()
            }
            let ink = Self.color(theme.branchTitleColor ?? "#252D2CFF") ?? .black
            ("Idea" as NSString).draw(at: NSPoint(x: 323, y: y + 5), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: ink
            ])
        }
        NSGraphicsContext.current = previous
        bitmap.size = NSSize(width: 392, height: 156)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        let result = (textView.string as NSString).replacingCharacters(in: affectedCharRange, with: replacementString ?? "")
        guard result.utf8.count <= 65_536 else {
            noteStatus.stringValue = L10n.text("Note exceeds 64 KiB or document limit", defaults: defaults)
            noteStatus.setAccessibilityValue(noteStatus.stringValue)
            return false
        }
        noteStatus.stringValue = ""
        return true
    }

    private func changed(_ didChange: Bool) {
        guard didChange else { refresh(); return }
        canvas.needsDisplay = true
        canvas.onChange?()
        refresh()
    }

    @objc func changeFontFamily(_ sender: Any?) {
        guard canvas.selectedRelationshipID == nil, ready() else { return }
        guard let family = familyPopup.selectedItem?.representedObject as? String else { refresh(); return }
        changed(canvas.model.setFont(family: family))
    }
    @objc func changeFontSize(_ sender: Any?) {
        guard canvas.selectedRelationshipID == nil, ready() else { return }
        if sender as? NSStepper === fontSizeStepper { fontSizeField.stringValue = "\(fontSizeStepper.doubleValue)" }
        guard let size = Double(fontSizeField.stringValue) else { refresh(); return }
        changed(canvas.model.setFont(size: size))
    }
    @objc func changeAlignment(_ sender: Any?) {
        guard canvas.selectedRelationshipID == nil, ready() else { return }
        let names = ["left", "center", "right", "justify"]
        guard names.indices.contains(alignmentControl.selectedSegment) else { return }
        changed(canvas.model.setAlignment(names[alignmentControl.selectedSegment]))
    }
    private func setSelectedColor(_ hex: String?) -> Bool {
        if let id = canvas.selectedRelationshipID {
            guard var edge = canvas.model.relationships.first(where: { $0.id == id }) else { return false }
            edge.color = hex
            return canvas.model.setRelationship(edge)
        }
        return hex.map { canvas.model.setBranchStroke(color: $0) } ?? canvas.model.resetStrokeColor()
    }
    @objc func changeColorSelection(_ sender: Any?) {
        guard ready() else { return }
        guard let choice = colorPopup.selectedItem?.representedObject as? String else { return }
        if choice == "More…" {
            refresh() // Opening the color panel does not itself change the selection or create undo.
            let panel = NSColorPanel.shared
            if let id = canvas.selectedRelationshipID {
                panel.color = canvas.model.relationships.first(where: { $0.id == id })?.color.flatMap(Self.color)
                    ?? .systemPurple
            } else if let hex = selectedNodes().first?.0.branchStrokeColor,
                      let color = Self.color(hex) { panel.color = color }
            colorPanelModel = canvas.model
            panel.setTarget(self)
            panel.setAction(#selector(changeStrokeColor(_:)))
            panel.makeKeyAndOrderFront(nil)
        } else if choice == "Default" { changed(setSelectedColor(nil)) }
        else if let hex = Self.colors.first(where: { $0.0 == choice })?.1 {
            changed(setSelectedColor(hex))
        } else { refresh() }
    }
    @objc func changeStrokeColor(_ sender: Any?) {
        guard colorPanelModel === canvas.model, ready(),
              let color = (sender as? NSColorPanel)?.color.usingColorSpace(.deviceRGB) else { return }
        changed(setSelectedColor(Self.hex(color)))
    }
    @objc func changeStrokeWidth(_ sender: Any?) {
        guard canvas.selectedRelationshipID == nil, ready() else { return }
        guard let choice = strokeWidthPopup.selectedItem?.representedObject as? String else { return }
        if choice == "Default" { changed(canvas.model.resetStrokeWidth()) }
        else if let width = Self.widths.first(where: { $0.0 == choice })?.1 {
            changed(canvas.model.setBranchStroke(width: width))
        } else { refresh() }
    }
    @objc func changeStrokeStyle(_ sender: Any?) {
        guard canvas.selectedRelationshipID == nil, ready() else { return }
        guard let value = (strokeStylePopup.selectedItem?.representedObject as? String)?.lowercased() else { return }
        if value == "default" { changed(canvas.model.resetStrokeStyle()) }
        else if value == "solid" || value == "dashed" {
            changed(canvas.model.setBranchStroke(style: value))
        }
    }
}
