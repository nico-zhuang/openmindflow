import AppKit

final class StyleInspector: NSView {
    private let canvas: MapCanvas
    let familyField = NSTextField()
    let fontSizeField = NSTextField()
    let fontSizeStepper = NSStepper()
    let alignmentControl = NSSegmentedControl(labels: ["L", "C", "R", "J"], trackingMode: .selectOne, target: nil, action: nil)
    let colorWell = NSColorWell()
    let colorState = NSTextField(labelWithString: "")
    let strokeWidthField = NSTextField()
    let strokeWidthSlider = NSSlider(value: 2, minValue: 0.5, maxValue: 12, target: nil, action: nil)
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
        }
        section("FONT")
        familyField.placeholderString = "Family"
        familyField.setAccessibilityLabel("Font family")
        familyField.target = self
        familyField.action = #selector(changeFontFamily(_:))
        row("Family", familyField)
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
        for (index, title) in ["Left", "Center", "Right", "Justify"].enumerated() {
            alignmentControl.setToolTip(title, forSegment: index)
        }
        alignmentControl.target = self
        alignmentControl.action = #selector(changeAlignment(_:))
        row("Align", alignmentControl)
        section("CONNECTION")
        colorWell.setAccessibilityLabel("Connection color")
        colorWell.target = self
        colorWell.action = #selector(changeStrokeColor(_:))
        colorWell.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let colorControls = NSStackView(views: [colorWell, colorState])
        colorControls.spacing = 8
        row("Color", colorControls)
        strokeWidthField.setAccessibilityLabel("Connection width")
        strokeWidthField.target = self
        strokeWidthField.action = #selector(changeStrokeWidth(_:))
        strokeWidthField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        strokeWidthSlider.setAccessibilityLabel("Connection width slider")
        strokeWidthSlider.target = self
        strokeWidthSlider.action = #selector(changeStrokeWidth(_:))
        let widthControls = NSStackView(views: [strokeWidthField, strokeWidthSlider])
        widthControls.spacing = 8
        row("Width", widthControls)
        strokeStylePopup.addItems(withTitles: ["Default", "Solid", "Dashed", "Mixed"])
        strokeStylePopup.setAccessibilityLabel("Connection line style")
        strokeStylePopup.target = self
        strokeStylePopup.action = #selector(changeStrokeStyle(_:))
        row("Line", strokeStylePopup)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view only") }

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
        for control: NSControl in [familyField, fontSizeField, fontSizeStepper, alignmentControl,
                                   colorWell, strokeWidthField, strokeWidthSlider, strokeStylePopup] {
            control.isEnabled = !nodes.isEmpty
        }
        guard let first = nodes.first else {
            familyField.stringValue = ""
            fontSizeField.stringValue = ""
            strokeWidthField.stringValue = ""
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
        familyField.stringValue = sameFamily ? families[0] : ""
        familyField.placeholderString = sameFamily ? "Family" : "Mixed"
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
        if sameColor, let color, color.count == 9, color.first == "#",
           let red = UInt8(color.dropFirst().prefix(2), radix: 16),
           let green = UInt8(color.dropFirst(3).prefix(2), radix: 16),
           let blue = UInt8(color.dropFirst(5).prefix(2), radix: 16),
           let alpha = UInt8(color.dropFirst(7).prefix(2), radix: 16) {
            colorWell.color = NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                                      blue: CGFloat(blue) / 255, alpha: CGFloat(alpha) / 255)
        } else { colorWell.color = .systemTeal }
        let width = first.0.branchStrokeWidth
        let sameWidth = nodes.allSatisfy { $0.0.branchStrokeWidth == width }
        strokeWidthField.stringValue = sameWidth ? width.map { String(format: "%g", Double($0)) } ?? "" : ""
        strokeWidthField.placeholderString = sameWidth ? (width == nil ? "Default" : "Width") : "Mixed"
        strokeWidthSlider.doubleValue = Double(width ?? 2)
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
        let family = familyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !family.isEmpty else { refresh(); return }
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
    @objc func changeStrokeColor(_ sender: Any?) {
        guard let color = colorWell.color.usingColorSpace(.deviceRGB) else { return }
        let components = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        let hex = "#" + components.map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
        changed(canvas.model.setBranchStroke(color: hex))
    }
    @objc func changeStrokeWidth(_ sender: Any?) {
        if sender as? NSSlider === strokeWidthSlider { strokeWidthField.stringValue = "\(strokeWidthSlider.doubleValue)" }
        guard let width = Double(strokeWidthField.stringValue) else { refresh(); return }
        changed(canvas.model.setBranchStroke(width: CGFloat(width)))
    }
    @objc func changeStrokeStyle(_ sender: Any?) {
        guard let value = strokeStylePopup.titleOfSelectedItem?.lowercased() else { return }
        if value == "default" { changed(canvas.model.resetStrokeStyle()) }
        else if value == "solid" || value == "dashed" {
            changed(canvas.model.setBranchStroke(style: value))
        }
    }
}
