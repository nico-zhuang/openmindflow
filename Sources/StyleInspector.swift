import AppKit

final class StyleInspector: NSView {
    private let canvas: MapCanvas
    private static let widths: [(String, CGFloat)] = [("Hairline", 0.75), ("Thin", 1.5),
                                                       ("Medium", 3), ("Bold", 5), ("Heavy", 8)]
    private static let colors = [("Teal", "#14B8A6FF"), ("Blue", "#3478F6FF"),
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

    override var intrinsicContentSize: NSSize { NSSize(width: 280, height: NSView.noIntrinsicMetric) }

    init(canvas: MapCanvas) {
        self.canvas = canvas
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16)
        ])
        func section(_ title: String) {
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: 11)
            stack.addArrangedSubview(label)
        }
        func row(_ title: String, _ control: NSView) {
            let label = NSTextField(labelWithString: title)
            label.widthAnchor.constraint(equalToConstant: 76).isActive = true
            let line = NSStackView(views: [label, control])
            line.orientation = .horizontal
            line.alignment = .centerY
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
        for (title, hex) in Self.colors {
            let item = colorPopup.menu!.addItem(withTitle: title, action: nil, keyEquivalent: "")
            if let color = Self.color(hex) {
                item.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                    color.setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                    return true
                }
            }
        }
        colorPopup.addItem(withTitle: "More…")
        colorPopup.setAccessibilityLabel("Connection color")
        colorPopup.target = self
        colorPopup.action = #selector(changeColorSelection(_:))
        let colorControls = NSStackView(views: [colorPopup, colorState])
        colorControls.spacing = 6
        row("Color", colorControls)
        strokeWidthPopup.addItems(withTitles: ["Default", "Mixed", "Custom"] + Self.widths.map(\.0))
        strokeWidthPopup.setAccessibilityLabel("Connection width")
        strokeWidthPopup.target = self
        strokeWidthPopup.action = #selector(changeStrokeWidth(_:))
        row("Width", strokeWidthPopup)
        strokeStylePopup.addItems(withTitles: ["Default", "Solid", "Dashed", "Mixed"])
        strokeStylePopup.setAccessibilityLabel("Connection line style")
        strokeStylePopup.target = self
        strokeStylePopup.action = #selector(changeStrokeStyle(_:))
        row("Line", strokeStylePopup)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view only") }

    private static func color(_ hex: String) -> NSColor? {
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
        let nodes = selectedNodes()
        for control: NSControl in [familyPopup, fontSizeField, fontSizeStepper, alignmentControl,
                                   colorPopup, strokeWidthPopup, strokeStylePopup] {
            control.isEnabled = !nodes.isEmpty
        }
        guard let first = nodes.first else {
            familyPopup.selectItem(withTitle: "Mixed")
            fontPreview.stringValue = "No selection"
            fontSizeField.stringValue = ""
            strokeWidthPopup.selectItem(withTitle: "Default")
            colorPopup.selectItem(withTitle: "Default")
            alignmentControl.selectedSegment = -1
            colorState.stringValue = "No selection"
            strokeStylePopup.selectItem(withTitle: "Default")
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
                unavailable.title = "Unavailable: \(families[0])"
                familyPopup.select(unavailable)
            }
            fontPreview.stringValue = "Aa 字"
            fontPreview.font = NSFont(name: families[0], size: 18) ?? .systemFont(ofSize: 18)
        } else {
            familyPopup.selectItem(withTitle: "Mixed")
            fontPreview.stringValue = "Mixed"
            fontPreview.font = .systemFont(ofSize: 13)
        }
        let sameSize = sizes.allSatisfy { $0 == sizes[0] }
        fontSizeField.stringValue = sameSize ? String(format: "%g", sizes[0]) : ""
        fontSizeField.placeholderString = sameSize ? "Size" : "Mixed"
        fontSizeStepper.doubleValue = sizes[0]
        let alignment = first.0.textAlignment
        let sameAlignment = nodes.allSatisfy { $0.0.textAlignment == alignment }
        alignmentControl.selectedSegment = sameAlignment
            ? ["left", "center", "right", "justify"].firstIndex(of: alignment ?? "") ?? -1 : -1
        alignmentControl.toolTip = sameAlignment ? (alignment ?? "Default") : "Mixed"
        let color = first.0.branchStrokeColor
        let sameColor = nodes.allSatisfy { $0.0.branchStrokeColor == color }
        colorState.stringValue = sameColor ? (color == nil ? "Default" : "") : "Mixed"
        colorPopup.selectItem(withTitle: sameColor
            ? color.map { saved in Self.colors.first(where: { $0.1 == saved.uppercased() })?.0 ?? "Custom" }
                ?? "Default" : "Mixed")
        let width = first.0.branchStrokeWidth
        let sameWidth = nodes.allSatisfy { $0.0.branchStrokeWidth == width }
        strokeWidthPopup.selectItem(withTitle: sameWidth
            ? width.map { value in Self.widths.first(where: { $0.1 == value })?.0 ?? "Custom" }
                ?? "Default" : "Mixed")
        let style = first.0.strokeStyle
        strokeStylePopup.selectItem(withTitle: nodes.allSatisfy({ $0.0.strokeStyle == style })
                                        ? style.map { $0.capitalized } ?? "Default" : "Mixed")
    }

    private func changed(_ didChange: Bool) {
        guard didChange else { refresh(); return }
        canvas.needsDisplay = true
        canvas.onChange?()
        refresh()
    }

    @objc func changeFontFamily(_ sender: Any?) {
        guard let family = familyPopup.selectedItem?.representedObject as? String else { refresh(); return }
        changed(canvas.model.setFont(family: family))
    }
    @objc func changeFontSize(_ sender: Any?) {
        if sender as? NSStepper === fontSizeStepper { fontSizeField.stringValue = "\(fontSizeStepper.doubleValue)" }
        guard let size = Double(fontSizeField.stringValue) else { refresh(); return }
        changed(canvas.model.setFont(size: size))
    }
    @objc func changeAlignment(_ sender: Any?) {
        let names = ["left", "center", "right", "justify"]
        guard names.indices.contains(alignmentControl.selectedSegment) else { return }
        changed(canvas.model.setAlignment(names[alignmentControl.selectedSegment]))
    }
    @objc func changeColorSelection(_ sender: Any?) {
        guard let choice = colorPopup.titleOfSelectedItem else { return }
        if choice == "More…" {
            refresh() // Opening the color panel does not itself change the selection or create undo.
            let panel = NSColorPanel.shared
            if let hex = selectedNodes().first?.0.branchStrokeColor, let color = Self.color(hex) { panel.color = color }
            panel.setTarget(self)
            panel.setAction(#selector(changeStrokeColor(_:)))
            panel.makeKeyAndOrderFront(nil)
        } else if choice == "Default" { changed(canvas.model.resetStrokeColor()) }
        else if let hex = Self.colors.first(where: { $0.0 == choice })?.1 {
            changed(canvas.model.setBranchStroke(color: hex))
        } else { refresh() }
    }
    @objc func changeStrokeColor(_ sender: Any?) {
        guard let color = (sender as? NSColorPanel)?.color.usingColorSpace(.deviceRGB) else { return }
        let components = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        let hex = "#" + components.map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
        changed(canvas.model.setBranchStroke(color: hex))
    }
    @objc func changeStrokeWidth(_ sender: Any?) {
        guard let choice = strokeWidthPopup.titleOfSelectedItem else { return }
        if choice == "Default" { changed(canvas.model.resetStrokeWidth()) }
        else if let width = Self.widths.first(where: { $0.0 == choice })?.1 {
            changed(canvas.model.setBranchStroke(width: width))
        } else { refresh() }
    }
    @objc func changeStrokeStyle(_ sender: Any?) {
        guard let value = strokeStylePopup.titleOfSelectedItem?.lowercased() else { return }
        if value == "default" { changed(canvas.model.resetStrokeStyle()) }
        else if value == "solid" || value == "dashed" {
            changed(canvas.model.setBranchStroke(style: value))
        }
    }
}
