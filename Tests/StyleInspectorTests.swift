import AppKit

@main enum StyleInspectorTests {
    static func main() {
        _ = NSApplication.shared
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let childID = UUID(), rootID = UUID()
        var child = MapNode(id: childID, title: "Child", children: [], folded: false)
        child.fontFamily = "Helvetica"
        child.fontSize = 18
        child.textAlignment = "right"
        child.branchStrokeWidth = 3
        child.branchStrokeColor = "#0088CCFF"
        child.strokeStyle = "dashed"
        var root = MapNode(id: rootID, title: "Root", children: [child], folded: false)
        root.fontFamily = "Menlo"
        root.fontSize = 22
        root.textAlignment = "left"
        root.branchStrokeWidth = 1 // Imported custom thickness must survive refresh.
        root.branchStrokeColor = "#FF0000FF"
        root.strokeStyle = "solid"
        let model = MapModel(roots: [root], selected: rootID)
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 500, height: 320)
        let suite = "local.mindmap.inspector-l10n-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        let inspector = StyleInspector(canvas: canvas, defaults: defaults)
        inspector.frame = CGRect(x: 0, y: 0, width: 280, height: 550)
        let otherID = UUID()
        var other = MapNode(id: otherID, title: "Other", children: [], folded: false)
        other.location = SIMD2(550, 350)
        var relationRoot = root
        relationRoot.location = SIMD2(130, 150)
        let relationModel = MapModel(roots: [relationRoot, other], selected: rootID)
        let relationCanvas = MapCanvas(model: relationModel)
        relationCanvas.frame = CGRect(x: 0, y: 0, width: 900, height: 500)
        let relationInspector = StyleInspector(canvas: relationCanvas, defaults: defaults)
        var relationSelections = 0
        relationCanvas.onSelectionChange = { relationSelections += 1; relationInspector.refresh() }
        assert(relationModel.toggleSelection(otherID))
        relationCanvas.createRelationship(nil)
        let relationID = relationModel.relationships[0].id
        assert(relationCanvas.selectedRelationshipID == relationID && relationInspector.colorPopup.isEnabled &&
               relationInspector.colorPopup.titleOfSelectedItem == "Default" &&
               !relationInspector.familyPopup.isEnabled && !relationInspector.strokeWidthPopup.isEnabled &&
               !relationInspector.rootFillPopup.isEnabled &&
               !relationInspector.tabs.isEnabled(forSegment: 1) && !relationInspector.selectNotes(for: rootID))
        let windowsBeforeRelation = NSApp.windows.count
        relationInspector.colorPopup.selectItem(withTitle: "Blue")
        relationInspector.changeColorSelection(relationInspector.colorPopup)
        assert(NSApp.windows.count == windowsBeforeRelation && relationModel.relationships[0].color == "#3478F6FF" &&
               relationModel.roots[0].branchStrokeColor == "#FF0000FF" &&
               relationInspector.colorPopup.titleOfSelectedItem == "Blue")
        assert(relationModel.undo() && relationModel.relationships[0].color == nil &&
               relationModel.roots[0].branchStrokeColor == "#FF0000FF")
        relationCanvas.undo() // Undo creation through the canvas, not directly through the model.
        assert(relationModel.relationships.isEmpty && relationCanvas.selectedRelationshipID == nil &&
               relationInspector.tabs.isEnabled(forSegment: 1) &&
               relationInspector.colorPopup.titleOfSelectedItem == "Mixed",
               "Undoing creation must restore the multi-node color action and enable Notes")
        relationCanvas.redo()
        relationInspector.refresh()
        assert(relationCanvas.selectNode(rootID) && relationCanvas.selectedRelationshipID == nil &&
               relationInspector.tabs.isEnabled(forSegment: 1) && relationInspector.colorPopup.titleOfSelectedItem == "Custom")
        relationInspector.colorPopup.selectItem(withTitle: "Teal")
        relationInspector.changeColorSelection(relationInspector.colorPopup)
        assert(relationModel.roots[0].branchStrokeColor == "#14B8A6FF" && relationModel.relationships[0].color == nil)
        assert(relationCanvas.model.toggleSelection(otherID))
        relationCanvas.needsDisplay = true
        let beforeReplace = relationSelections
        // AppDelegate installs a whole document before fit emits the selection notification.
        relationCanvas.replacingModel = true
        relationCanvas.model = MapModel(roots: [relationRoot, other], selected: rootID)
        relationCanvas.branchStyles = [rootID: MindNodeVisualStyle(rgba: [0, 0.8, 0, 1], width: 3)]
        relationCanvas.embeddedTheme = nil
        relationCanvas.nativePresentation = [:]
        assert(relationSelections == beforeReplace, "Metadata setters must not refresh the inspector early")
        relationInspector.refresh()
        relationCanvas.replacingModel = false
        _ = relationCanvas.fitMapInView()
        assert(relationSelections == beforeReplace + 1,
               "Replacing {A,B} with {A} must notify once after all metadata")
        relationCanvas.replacingModel = true
        relationCanvas.model = MapModel(roots: [relationRoot, other], selected: otherID)
        relationCanvas.branchStyles = [:]
        relationCanvas.embeddedTheme = nil
        relationCanvas.nativePresentation = [:]
        assert(relationSelections == beforeReplace + 1, "New UUID must wait for document installation")
        relationInspector.refresh()
        relationCanvas.replacingModel = false
        _ = relationCanvas.fitMapInView()
        assert(relationSelections == beforeReplace + 2,
               "Changed selected UUID must emit exactly one deferred selection notification")
        let afterReplace = relationSelections
        relationCanvas.needsDisplay = true
        assert(relationSelections == afterReplace)
        relationCanvas.model = MapModel(roots: [relationRoot, other], selected: otherID)
        assert(relationSelections == afterReplace)
        relationInspector.refresh()
        relationCanvas.needsDisplay = true
        assert(relationSelections == afterReplace,
               "Replacing a model with the same selected UUID relies on explicit inspector refresh")
        assert(relationCanvas.model.toggleSelection(rootID))
        relationCanvas.createRelationship(nil)
        let arrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{f701}",
            charactersIgnoringModifiers: "\u{f701}", isARepeat: false, keyCode: 125)!
        relationCanvas.keyDown(with: arrow)
        assert(relationCanvas.selectedRelationshipID == nil && relationCanvas.model.selected == otherID &&
               relationInspector.tabs.isEnabled(forSegment: 1) &&
               relationInspector.colorPopup.titleOfSelectedItem == "Default",
               "Arrow navigation to a node must leave relationship editing")
        assert(relationCanvas.model.toggleSelection(rootID))
        relationCanvas.createRelationship(nil)
        let previousEdge = relationCanvas.model.relationships.last!
        assert(relationCanvas.selectedRelationshipID == previousEdge.id)
        let replacement = MapModel(roots: [relationRoot, other], selected: rootID)
        replacement.relationships = [previousEdge] // Even a reused UUID belongs to the new document.
        relationInspector.colorPanelModel = relationCanvas.model // Simulate an open old-document More panel without ordering it.
        relationCanvas.model = replacement
        assert(relationCanvas.selectedRelationshipID == nil && replacement.relationships[0].id == previousEdge.id,
               "Replacing the document must discard an old relationship target even if its UUID recurs")
        // Simulate delayed native panel actions without opening or ordering the shared panel.
        let panel = NSColorPanel.shared
        assert(!panel.isVisible && !panel.isKeyWindow)
        panel.color = .systemGreen
        let untouched = replacement.roots
        let untouchedCanvasColor = replacement.canvasColor
        relationInspector.changeStrokeColor(panel)
        _ = relationInspector.perform(NSSelectorFromString("changeRootPanelColor:"), with: panel)
        _ = relationInspector.perform(NSSelectorFromString("changeCanvasPanelColor:"), with: panel)
        assert(replacement.roots == untouched && replacement.canvasColor == untouchedCanvasColor &&
               !panel.isVisible && !panel.isKeyWindow,
               "An old-document native panel action must not mutate the replacement document")
        relationInspector.colorPopup.selectItem(withTitle: "Blue")
        relationInspector.changeColorSelection(relationInspector.colorPopup)
        assert(replacement.roots[0].branchStrokeColor == "#3478F6FF",
               "Presets still edit the new document")
        relationInspector.colorPanelModel = replacement // Model captured by current-document More (no panel ordering).
        relationInspector.changeStrokeColor(panel)
        let currentColor = StyleInspector.hex(panel.color.usingColorSpace(.deviceRGB)!)
        assert(replacement.roots[0].branchStrokeColor == currentColor,
               "Current-document More color still edits the selected node")
        _ = relationInspector.perform(NSSelectorFromString("changeRootPanelColor:"), with: panel)
        _ = relationInspector.perform(NSSelectorFromString("changeCanvasPanelColor:"), with: panel)
        assert(replacement.roots[0].rootFillColor == currentColor && replacement.canvasColor == currentColor &&
               !panel.isVisible && !panel.isKeyWindow,
               "Current-document native callbacks remain functional without ordering a panel")
        do {
        let model = MapModel(roots: [root], selected: rootID)
        let noteCanvas = MapCanvas(model: model)
        let inspector = StyleInspector(canvas: noteCanvas, defaults: defaults)
        assert(inspector.tabs.segmentCount == 3 && (0..<3).allSatisfy {
            inspector.tabs.image(forSegment: $0) != nil &&
            !(inspector.tabs.toolTip(forSegment: $0) ?? "").isEmpty
        })
        assert(inspector.backgroundPopup.itemTitles == ["Follow System", "Light", "Dark", "More…"])
        assert(inspector.styleScroll.hasVerticalScroller && inspector.notesScroll.hasVerticalScroller)
        if inspector.notesScroll.contentInsets.bottom < inspector.noteStatus.intrinsicContentSize.height + 5 {
            fputs("Notes editor must reserve bottom space above its validation status\n", stderr)
            exit(1)
        }
        assert(inspector.themeButtons.count == 3)
        inspector.frame = NSRect(x: 0, y: 0, width: 260, height: 250)
        inspector.layoutSubtreeIfNeeded()
        guard let themes = inspector.themeButtons.first?.superview,
              let themeScroll = descendants(inspector).compactMap({ $0 as? NSScrollView }).first(where: {
                  $0.documentView.map { themes === $0 || themes.isDescendant(of: $0) } ?? false
              }), let themeDocument = themeScroll.documentView,
              inspector.themeButtons.allSatisfy({ $0.frame.width > 0 && $0.frame.height > 0 }),
              themeDocument.frame.width > 0,
              themeDocument.frame.height > themeScroll.contentView.bounds.height,
              themeScroll.hasVerticalScroller else {
            fputs("All three theme cards need a sized, vertically scrollable document at 260×250\n", stderr)
            exit(1)
        }
        inspector.selectNotes(for: rootID)
        inspector.noteTextView.string = "One note"
        assert(inspector.commitNoteEditing() && model.roots[0].note == "One note")
        assert(inspector.commitNoteEditing() && model.undo() && model.roots[0].note == nil && !model.undo())
        inspector.refresh()
        if !inspector.noteTextView.string.isEmpty {
            fputs("Model Undo must refresh the visible Notes editor on the same node\n", stderr)
            exit(1)
        }
        inspector.noteTextView.string = "Original root"
        model.selectOnly(childID)
        inspector.refresh()
        assert(model.roots[0].note == "Original root" && model.roots[0].children[0].note == nil)
        assert(inspector.noteTextView.string.isEmpty)
        inspector.noteTextView.string = String(repeating: "界", count: 22_000)
        assert(!inspector.commitNoteEditing() && inspector.noteTextView.string.utf8.count > 65_536)
        inspector.noteTextView.string = "Child note"
        assert(inspector.commitNoteEditing() && model.roots[0].children[0].note == "Child note")
        model.selectOnly(rootID)
        assert(model.setNote("ID edit", for: childID) && model.roots[0].children[0].note == "ID edit" &&
               model.selected == rootID && model.undo() && model.roots[0].children[0].note == "Child note")
        model.selectOnly(rootID)
        inspector.refresh()
        inspector.themeButtons[0].performClick(nil)
        assert(model.theme == InspectorTheme.tropical.rawValue && model.undo() && model.theme == nil)
        inspector.backgroundPopup.selectItem(withTitle: "Dark")
        inspector.changeCanvasBackground(inspector.backgroundPopup)
        assert(model.canvasColor == "#141414FF" && model.undo() && model.canvasColor == nil)
        inspector.rootShapePopup.selectItem(withTitle: "Rectangle")
        inspector.changeRootShape(inspector.rootShapePopup)
        assert(model.roots[0].rootShape == "rectangle" && model.undo())
        guard ["Teal", "Blue", "Coral", "Gold", "Gray"].allSatisfy({
            inspector.rootFillPopup.item(withTitle: $0)?.image != nil
        }) && inspector.rootFillPopup.itemTitles.last == "More…" else {
            fputs("Root fill needs five native quick-color swatches and More…\n", stderr)
            exit(1)
        }
        inspector.rootFillPopup.selectItem(withTitle: "Blue")
        NSApp.sendAction(inspector.rootFillPopup.action!, to: inspector.rootFillPopup.target,
                         from: inspector.rootFillPopup)
        guard model.roots[0].rootFillColor == "#3478F6FF",
              inspector.rootFillPopup.titleOfSelectedItem == "Blue",
              model.undo(), model.roots[0].rootFillColor == nil else {
            fputs("Root fill preset must select the actual color and undo cleanly\n", stderr)
            exit(1)
        }
        inspector.refresh()
        inspector.rootWidthPopup.selectItem(withTitle: "Medium (240 pt)")
        inspector.changeRootWidth(inspector.rootWidthPopup)
        assert(model.roots[0].width == 240 && model.undo())
        let candyPreview = inspector.themeButtons[2].image!
        let previewBitmap = candyPreview.representations.compactMap { $0 as? NSBitmapImageRep }.first!
        let pink = NSColor(srgbRed: 239/255, green: 23/255, blue: 96/255, alpha: 1)
        let actual = previewBitmap.colorAt(x: 110, y: 70)!.usingColorSpace(.sRGB)!
        let themeCanvas = MapCanvas(model: MapModel(roots: [root], selected: rootID, theme: InspectorTheme.candyland.rawValue))
        _ = themeCanvas.model.selectNodes([]) // Selected nodes receive a blue translucent overlay.
        themeCanvas.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
        let themeBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: themeBitmap)
        themeCanvas.draw(themeCanvas.bounds)
        NSGraphicsContext.current = previous
        let themedBox = themeCanvas.frameForAccessibility(rootID)!
        let liveColor = themeBitmap.colorAt(x: Int(themedBox.maxX - 15),
            y: themeBitmap.pixelsHigh - Int(themedBox.midY) - 1)!.usingColorSpace(.sRGB)!
        for expected in [pink, liveColor] {
            if abs(actual.redComponent - expected.redComponent) >= 0.05 ||
               abs(actual.greenComponent - expected.greenComponent) >= 0.05 ||
               abs(actual.blueComponent - expected.blueComponent) >= 0.05 {
                fputs("Candyland card \(actual) differs from canvas/palette \(expected)\n", stderr)
                exit(1)
            }
        }
        func matches(_ pixel: NSColor?, hex: String) -> Bool {
            guard let pixel = pixel?.usingColorSpace(.sRGB),
                  let rgb = UInt32(hex.dropFirst().prefix(6), radix: 16) else { return false }
            let channels = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
            return zip(channels, [16, 8, 0]).allSatisfy { channel, shift in
                abs(channel - CGFloat((rgb >> shift) & 255) / 255) < 0.06
            }
        }
        for (index, theme) in InspectorTheme.allCases.enumerated() {
            let card = inspector.themeButtons[index].image!.representations.compactMap { $0 as? NSBitmapImageRep }.first!
            guard matches(card.colorAt(x: 110, y: 70), hex: theme.rootFill),
                  theme.branchColors.prefix(3).allSatisfy({ hex in
                      (0..<card.pixelsHigh).contains { y in matches(card.colorAt(x: 320, y: y), hex: hex) }
                  }) else {
                fputs("Theme card must show the real root and all three branch colors: \(theme)\n", stderr)
                exit(1)
            }
            inspector.themeButtons[index].performClick(nil)
            assert(model.theme == theme.rawValue && model.undo())
        }
        assert(inspector.tabs.toolTip(forSegment: 1) == "Notes" &&
               !(0..<inspector.tabs.segmentCount).contains { inspector.tabs.toolTip(forSegment: $0) == "Tags" })
        inspector.selectNotes(for: rootID)
        assert(inspector.tabs.selectedSegment == 1 && inspector.noteTextView.string == "Original root")
        inspector.noteTextView.string = "Original root + newest keystroke"
        assert(noteCanvas.commitEditing() && model.roots[0].note == inspector.noteTextView.string)
        let reopened = try! JSONDecoder().decode([MapNode].self, from: JSONEncoder().encode(model.roots))
        assert(reopened[0].note == "Original root + newest keystroke" && model.undo())
        inspector.refresh()
        assert(inspector.noteTextView.string == "Original root")
        var reloadedRoot = root
        reloadedRoot.note = "Externally newer note"
        noteCanvas.model = MapModel(roots: [reloadedRoot], selected: rootID)
        inspector.refresh() // File Open calls this after its appearance metadata is installed.
        assert(inspector.noteTextView.string == "Externally newer note")
        }
        let popups = descendants(inspector).compactMap { $0 as? NSPopUpButton }
        let popupLabels = Set(popups.compactMap { $0.accessibilityLabel() })
        guard popupLabels.isSuperset(of: ["Font family", "Connection color", "Connection width"]),
              !descendants(inspector).contains(where: { $0 is NSColorWell || $0 is NSSlider }),
              inspector.familyPopup.numberOfItems > 20,
              inspector.familyPopup.item(withTitle: "Helvetica")?.attributedTitle?.attribute(
                .font, at: 0, effectiveRange: nil) is NSFont,
              !inspector.fontPreview.stringValue.isEmpty,
              (0..<4).allSatisfy({ inspector.alignmentControl.image(forSegment: $0) != nil &&
                  (inspector.alignmentControl.label(forSegment: $0) ?? "").isEmpty &&
                  inspector.alignmentControl.toolTip(forSegment: $0) != nil }),
              inspector.colorPopup.itemTitles.suffix(1) == ["More…"],
              ["Teal", "Blue", "Coral", "Gold", "Gray"].allSatisfy({ inspector.colorPopup.item(withTitle: $0)?.image != nil }),
              inspector.strokeWidthPopup.itemTitles == ["Default", "Mixed", "Custom", "Hairline", "Thin", "Medium", "Bold", "Heavy"] else {
            fputs("Inspector needs installed-font previews, SF alignment, preset swatches, and discrete widths\n", stderr)
            exit(1)
        }
        guard model.toggleSelection(childID), model.selectedIDs == [rootID, childID] else {
            fputs("Inspector test requires both selected nodes\n", stderr); exit(1)
        }
        inspector.refresh()
        guard inspector.familyPopup.titleOfSelectedItem == "Mixed",
              inspector.fontSizeField.placeholderString == "Mixed",
              inspector.alignmentControl.selectedSegment == -1,
              inspector.strokeWidthPopup.titleOfSelectedItem == "Mixed",
              inspector.strokeStylePopup.titleOfSelectedItem == "Mixed",
              inspector.colorState.stringValue == "Mixed" else {
            fputs("Multi-selection must expose mixed native inspector controls\n", stderr); exit(1)
        }
        model.selectOnly(rootID)
        inspector.refresh()
        guard inspector.strokeWidthPopup.titleOfSelectedItem == "Custom", model.roots == [root] else {
            fputs("Imported non-preset width must display Custom without quantizing model\n", stderr); exit(1)
        }
        model.toggleSelection(childID)
        inspector.refresh()
        var changes = 0
        canvas.onChange = { changes += 1 }
        inspector.familyPopup.selectItem(withTitle: "Helvetica")
        inspector.changeFontFamily(inspector.familyPopup)
        guard model.roots[0].fontFamily == "Helvetica", model.roots[0].children[0].fontFamily == "Helvetica",
              model.roots[0].fontSize == 22, model.roots[0].children[0].fontSize == 18,
              changes == 1, model.undo(), model.roots == [root] else {
            fputs("Font dropdown must preserve mixed sizes and undo once\n", stderr); exit(1)
        }
        inspector.fontSizeField.stringValue = "24"
        inspector.changeFontSize(inspector.fontSizeField)
        guard model.roots[0].fontFamily == "Menlo", model.roots[0].children[0].fontFamily == "Helvetica",
              model.roots[0].fontSize == 24, model.roots[0].children[0].fontSize == 24,
              changes == 2, model.undo(), model.roots == [root],
              model.selectedIDs == [rootID, childID] else {
            fputs("Size edit must preserve mixed families and undo all selected nodes once\n", stderr); exit(1)
        }
        inspector.alignmentControl.selectedSegment = 1
        inspector.changeAlignment(inspector.alignmentControl)
        guard model.roots[0].textAlignment == "center", model.roots[0].children[0].textAlignment == "center",
              changes == 3, model.undo(), model.roots == [root] else {
            fputs("Symbol alignment must apply atomically to both nodes\n", stderr); exit(1)
        }
        inspector.strokeStylePopup.selectItem(withTitle: "Solid")
        inspector.changeStrokeStyle(inspector.strokeStylePopup)
        guard model.roots[0].strokeStyle == "solid", model.roots[0].children[0].strokeStyle == "solid",
              model.roots[0].branchStrokeColor == "#FF0000FF",
              model.roots[0].children[0].branchStrokeColor == "#0088CCFF",
              changes == 4, model.undo(), model.roots == [root] else {
            fputs("Line style edit must preserve mixed stroke colors and undo once\n", stderr); exit(1)
        }
        inspector.strokeWidthPopup.selectItem(withTitle: "Bold")
        inspector.changeStrokeWidth(inspector.strokeWidthPopup)
        guard model.roots[0].branchStrokeWidth == 5, model.roots[0].children[0].branchStrokeWidth == 5,
              changes == 5, model.undo(), model.roots == [root] else {
            fputs("Discrete Bold width must apply to both nodes in one undo\n", stderr); exit(1)
        }
        let windowsBeforePreset = NSApp.windows.count
        inspector.colorPopup.selectItem(withTitle: "Blue")
        inspector.changeColorSelection(inspector.colorPopup)
        guard NSApp.windows.count == windowsBeforePreset,
              model.roots[0].branchStrokeColor == "#3478F6FF",
              model.roots[0].children[0].branchStrokeColor == "#3478F6FF",
              changes == 6, model.undo(), model.roots == [root] else {
            fputs("Preset Blue must set the same color on both selected nodes\n", stderr); exit(1)
        }
        inspector.strokeStylePopup.selectItem(withTitle: "Default")
        inspector.changeStrokeStyle(inspector.strokeStylePopup)
        guard model.roots[0].strokeStyle == nil, model.roots[0].children[0].strokeStyle == nil,
              model.roots[0].branchStrokeColor == "#FF0000FF",
              model.roots[0].children[0].branchStrokeColor == "#0088CCFF",
              changes == 7, model.undo(), model.roots == [root] else {
            fputs("Default line style must preserve colors and undo once\n", stderr); exit(1)
        }
        inspector.colorPopup.selectItem(withTitle: "Default")
        inspector.changeColorSelection(inspector.colorPopup)
        guard model.roots[0].branchStrokeColor == nil,
              model.roots[0].children[0].branchStrokeColor == nil,
              model.roots[0].branchStrokeWidth == 1, changes == 8,
              model.undo(), model.roots == [root] else {
            fputs("Default color must restore inherited source colors on all nodes, preserving widths and one undo\n", stderr); exit(1)
        }
        inspector.strokeWidthPopup.selectItem(withTitle: "Default")
        inspector.changeStrokeWidth(inspector.strokeWidthPopup)
        guard model.roots[0].branchStrokeWidth == nil,
              model.roots[0].children[0].branchStrokeWidth == nil,
              model.roots[0].branchStrokeColor == "#FF0000FF", changes == 9,
              model.undo(), model.roots == [root] else {
            fputs("Default width must restore inherited source widths without dropping custom colors\n", stderr); exit(1)
        }
        inspector.fontSizeField.stringValue = "not a size"
        inspector.changeFontSize(inspector.fontSizeField)
        inspector.strokeWidthPopup.selectItem(withTitle: "Custom")
        inspector.changeStrokeWidth(inspector.strokeWidthPopup)
        guard changes == 9, model.roots == [root] else {
            fputs("Invalid or placeholder inspector input must leave nodes untouched\n", stderr); exit(1)
        }
        for width: CGFloat in [260, 320] {
            inspector.frame.size.width = width
            inspector.layoutSubtreeIfNeeded()
            guard let label = descendants(inspector).compactMap({ $0 as? NSTextField }).first(where: {
                $0.stringValue == "Canvas Background"
            }), label.frame.width >= label.intrinsicContentSize.width - 0.5,
                inspector.backgroundPopup.frame.width >= inspector.backgroundPopup.intrinsicContentSize.width - 0.5,
                inspector.colorPopup.frame.width >= 120 else {
                fputs("Canvas label, background selector, and native color selector must remain readable at 260–320pt\n", stderr)
                exit(1)
            }
            let controls: [NSView] = [inspector.familyPopup, inspector.fontPreview,
                                      inspector.fontSizeField, inspector.alignmentControl,
                                      inspector.colorPopup, inspector.strokeWidthPopup, inspector.strokeStylePopup]
            guard controls.allSatisfy({ control in
                let rect = inspector.convert(control.bounds, from: control)
                return rect.minX >= 0 && rect.maxX <= width + 0.5 && rect.width > 0
            }), inspector.familyPopup.isEnabled, inspector.colorPopup.isEnabled else {
                fputs("Native inspector controls must fit in 260–320pt sidebars\n", stderr); exit(1)
            }
        }
        var unavailable = MapNode(id: UUID(), title: "Imported", children: [], folded: false)
        unavailable.fontFamily = "Unavailable-MindMap-Font"
        unavailable.branchStrokeColor = "#010203FF"
        let importedModel = MapModel(roots: [unavailable], selected: unavailable.id)
        let importedInspector = StyleInspector(canvas: MapCanvas(model: importedModel))
        guard importedInspector.familyPopup.titleOfSelectedItem == "Unavailable: Unavailable-MindMap-Font",
              importedInspector.colorPopup.titleOfSelectedItem == "Custom",
              importedModel.roots == [unavailable] else {
            fputs("Unavailable imported font and custom color must remain intact on refresh\n", stderr); exit(1)
        }
        guard inspector.colorPopup.item(withTitle: "More…")?.representedObject as? String == "More…",
              inspector.colorPopup.action == #selector(StyleInspector.changeColorSelection(_:)),
              inspector.colorPopup.target === inspector,
              model.roots == [root], changes == 9 else {
            fputs("More must remain wired without opening a panel or changing the model\n", stderr); exit(1)
        }
        defaults.setVolatileDomain(["language": "zh-Hans"], forName: UserDefaults.argumentDomain)
        let unchangedRoots = model.roots, beforeLanguageChange = changes
        inspector.localize()
        inspector.frame.size.width = 260
        inspector.layoutSubtreeIfNeeded()
        guard let canvasLabel = descendants(inspector).compactMap({ $0 as? NSTextField }).first(where: {
            $0.stringValue == "画布背景"
        }), canvasLabel.frame.width >= canvasLabel.intrinsicContentSize.width - 0.5,
            inspector.backgroundPopup.frame.width >= inspector.backgroundPopup.intrinsicContentSize.width - 0.5,
            inspector.rootFillPopup.item(withTitle: "蓝色")?.representedObject as? String == "Blue" else {
            fputs("Chinese labels, selectors, and root colors must remain legible at 260pt\n", stderr)
            exit(1)
        }
        let labels = descendants(inspector).compactMap { ($0 as? NSTextField)?.stringValue }
        guard ["字体", "连接线", "字号", "宽度"].allSatisfy(labels.contains),
              inspector.familyPopup.item(at: 0)?.title == "混合",
              inspector.fontSizeField.placeholderString == "混合",
              inspector.alignmentControl.toolTip(forSegment: 0) == "左对齐",
              inspector.alignmentControl.accessibilityLabel() == "段落对齐",
              inspector.colorPopup.itemTitles.suffix(1) == ["更多…"],
              inspector.colorPopup.item(withTitle: "蓝色")?.representedObject as? String == "Blue",
              inspector.colorPopup.accessibilityLabel() == "连接线颜色",
               inspector.tabs.toolTip(forSegment: 0) == "样式",
               inspector.tabs.toolTip(forSegment: 1) == "注释",
               inspector.tabs.toolTip(forSegment: 2) == "主题",
               inspector.backgroundPopup.itemTitles == ["跟随系统", "浅色", "深色", "更多…"],
              inspector.strokeWidthPopup.item(withTitle: "粗")?.representedObject as? String == "Bold",
              inspector.strokeStylePopup.item(withTitle: "虚线")?.representedObject as? String == "Dashed",
              !NSApp.windows.contains(where: { $0 is NSColorPanel && $0.isVisible }), model.roots == unchangedRoots,
              changes == beforeLanguageChange else {
            fputs("Chinese inspector must relabel visible rows, menus, placeholders, and AX without changing model or opening panels\n", stderr)
            exit(1)
        }
        inspector.strokeWidthPopup.selectItem(withTitle: "粗")
        inspector.changeStrokeWidth(inspector.strokeWidthPopup)
        guard model.roots[0].branchStrokeWidth == 5, model.roots[0].children[0].branchStrokeWidth == 5,
              changes == beforeLanguageChange + 1, model.undo(), model.roots == [root] else {
            fputs("Localized width choice must retain atomic English-key model semantics\n", stderr); exit(1)
        }
        inspector.colorPopup.selectItem(withTitle: "蓝色")
        inspector.changeColorSelection(inspector.colorPopup)
        guard model.roots[0].branchStrokeColor == "#3478F6FF",
              model.roots[0].children[0].branchStrokeColor == "#3478F6FF",
              changes == beforeLanguageChange + 2, model.undo(), model.roots == [root] else {
            fputs("Localized color choice must retain atomic model hex values\n", stderr); exit(1)
        }
        defaults.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        inspector.localize()
        guard inspector.colorPopup.item(withTitle: "Blue") != nil,
              inspector.strokeWidthPopup.item(withTitle: "Bold") != nil,
              model.roots == [root] else {
            fputs("Switching back to English must immediately restore UI labels only\n", stderr); exit(1)
        }
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        print("style inspector preset menus, localized labels and mixed selection passed")
    }
}
