import AppKit

@main enum StyleInspectorTests {
    static func main() {
        _ = NSApplication.shared
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
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
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
        inspector.colorPopup.selectItem(withTitle: "More…")
        inspector.changeColorSelection(inspector.colorPopup)
        guard NSColorPanel.shared.isVisible, model.roots == [root], changes == 9 else {
            fputs("Only explicit More must open the native color panel without changing model\n", stderr); exit(1)
        }
        NSColorPanel.shared.orderOut(nil)
        defaults.setVolatileDomain(["language": "zh-Hans"], forName: UserDefaults.argumentDomain)
        let unchangedRoots = model.roots, beforeLanguageChange = changes
        inspector.localize()
        let labels = descendants(inspector).compactMap { ($0 as? NSTextField)?.stringValue }
        guard ["字体", "连接线", "字号", "宽度"].allSatisfy(labels.contains),
              inspector.familyPopup.item(at: 0)?.title == "混合",
              inspector.fontSizeField.placeholderString == "混合",
              inspector.alignmentControl.toolTip(forSegment: 0) == "左对齐",
              inspector.alignmentControl.accessibilityLabel() == "段落对齐",
              inspector.colorPopup.itemTitles.suffix(1) == ["更多…"],
              inspector.colorPopup.item(withTitle: "蓝色")?.representedObject as? String == "Blue",
              inspector.colorPopup.accessibilityLabel() == "连接线颜色",
              inspector.strokeWidthPopup.item(withTitle: "粗")?.representedObject as? String == "Bold",
              inspector.strokeStylePopup.item(withTitle: "虚线")?.representedObject as? String == "Dashed",
              !NSColorPanel.shared.isVisible, model.roots == unchangedRoots,
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
