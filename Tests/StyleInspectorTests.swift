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
        root.branchStrokeWidth = 1
        root.branchStrokeColor = "#FF0000FF"
        root.strokeStyle = "solid"
        let model = MapModel(roots: [root], selected: rootID)
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 500, height: 320)
        let inspector = StyleInspector(canvas: canvas)
        inspector.frame = CGRect(x: 0, y: 0, width: 280, height: 550)
        guard model.toggleSelection(childID), model.selectedIDs == [rootID, childID] else {
            fputs("Inspector test requires both selected nodes\n", stderr); exit(1)
        }
        inspector.refresh()
        guard inspector.familyField.placeholderString == "Mixed",
              inspector.fontSizeField.placeholderString == "Mixed",
              inspector.alignmentControl.selectedSegment == -1,
              inspector.alignmentControl.segmentCount == 4,
              inspector.strokeWidthField.placeholderString == "Mixed",
              inspector.strokeStylePopup.titleOfSelectedItem == "Mixed",
              inspector.colorState.stringValue == "Mixed" else {
            fputs("Multi-selection must expose mixed native inspector controls\n", stderr); exit(1)
        }
        var changes = 0
        canvas.onChange = { changes += 1 }
        inspector.familyField.stringValue = "Avenir"
        inspector.changeFontFamily(inspector.familyField)
        guard model.roots[0].fontFamily == "Avenir", model.roots[0].children[0].fontFamily == "Avenir",
              model.roots[0].fontSize == 22, model.roots[0].children[0].fontSize == 18,
              changes == 1, model.undo(), model.roots == [root] else {
            fputs("Font family edit must preserve mixed sizes and undo once\n", stderr); exit(1)
        }
        inspector.fontSizeField.stringValue = "24"
        inspector.changeFontSize(inspector.fontSizeField)
        guard model.roots[0].fontFamily == "Menlo", model.roots[0].children[0].fontFamily == "Helvetica",
              model.roots[0].fontSize == 24, model.roots[0].children[0].fontSize == 24,
              changes == 2, model.undo(), model.roots == [root],
              model.selectedIDs == [rootID, childID] else {
            fputs("Size edit must preserve mixed families and undo all selected nodes in one step\n", stderr); exit(1)
        }
        inspector.alignmentControl.selectedSegment = 1
        inspector.changeAlignment(inspector.alignmentControl)
        guard model.roots[0].textAlignment == "center", model.roots[0].children[0].textAlignment == "center",
              changes == 3, model.undo(), model.roots == [root] else {
            fputs("Alignment edit must apply atomically to both nodes\n", stderr); exit(1)
        }
        inspector.strokeStylePopup.selectItem(withTitle: "Solid")
        inspector.changeStrokeStyle(inspector.strokeStylePopup)
        guard model.roots[0].strokeStyle == "solid", model.roots[0].children[0].strokeStyle == "solid",
              model.roots[0].branchStrokeColor == "#FF0000FF",
              model.roots[0].children[0].branchStrokeColor == "#0088CCFF",
              changes == 4, model.undo(), model.roots == [root] else {
            fputs("Stroke style edit must preserve mixed stroke colors and undo once\n", stderr); exit(1)
        }
        inspector.strokeWidthField.stringValue = "4"
        inspector.changeStrokeWidth(inspector.strokeWidthField)
        guard model.roots[0].branchStrokeWidth == 4, model.roots[0].children[0].branchStrokeWidth == 4,
              changes == 5, model.undo(), model.roots == [root] else {
            fputs("Stroke width edit must apply to both selected nodes in one undo\n", stderr); exit(1)
        }
        inspector.colorWell.color = NSColor(deviceRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        inspector.changeStrokeColor(inspector.colorWell)
        guard model.roots[0].branchStrokeColor == "#336699FF",
              model.roots[0].children[0].branchStrokeColor == "#336699FF",
              changes == 6, model.undo(), model.roots == [root] else {
            fputs("Color well must set the same RGBA stroke on both selected nodes\n", stderr); exit(1)
        }
        inspector.strokeStylePopup.selectItem(withTitle: "Default")
        inspector.changeStrokeStyle(inspector.strokeStylePopup)
        guard model.roots[0].strokeStyle == nil, model.roots[0].children[0].strokeStyle == nil,
              model.roots[0].branchStrokeColor == "#FF0000FF",
              model.roots[0].children[0].branchStrokeColor == "#0088CCFF",
              changes == 7, model.undo(), model.roots == [root] else {
            fputs("Default line style must reset only style on all selected nodes, preserving colors and undo once\n", stderr); exit(1)
        }
        inspector.fontSizeField.stringValue = "not a size"
        inspector.changeFontSize(inspector.fontSizeField)
        inspector.strokeWidthField.stringValue = "NaN"
        inspector.changeStrokeWidth(inspector.strokeWidthField)
        guard changes == 7, model.roots == [root] else {
            fputs("Invalid inspector input must leave selected nodes untouched\n", stderr); exit(1)
        }
        for width: CGFloat in [260, 320] {
            inspector.frame.size.width = width
            inspector.layoutSubtreeIfNeeded()
            let controls: [NSView] = [inspector.familyField, inspector.fontSizeField,
                                      inspector.alignmentControl, inspector.colorWell,
                                      inspector.strokeWidthField, inspector.strokeWidthSlider,
                                      inspector.strokeStylePopup]
            guard controls.allSatisfy({ control in
                let rect = inspector.convert(control.bounds, from: control)
                return rect.minX >= 0 && rect.maxX <= width + 0.5 && rect.width > 0
            }), inspector.familyField.isEnabled, inspector.colorWell.isEnabled else {
                fputs("Native inspector controls must fit in 260–320pt sidebars\n", stderr); exit(1)
            }
        }
        print("style inspector multi-selection and native controls passed (no windows)")
    }
}
