import AppKit

@main enum RootTitleAlignmentTests {
    static func main() {
        _ = NSApplication.shared // Detached canvas only; no ordered/key window.
        func editorAlignment(root: MapNode, imported: String? = nil, child: Bool = false) -> NSTextAlignment {
            let node = child ? root.children[0] : root
            let canvas = MapCanvas(model: MapModel(roots: [root], selected: node.id))
            canvas.frame = CGRect(x: 0, y: 0, width: 1100, height: 700)
            if let imported {
                let font = MindNodeFontMetadata(family: nil, pointSize: nil, color: nil,
                    alignment: imported, alignmentCode: nil, bold: nil, italic: nil)
                canvas.nativePresentation[node.id] = MindNodePresentation(location: nil,
                    maxWidth: nil, allowToShrinkWidth: nil, font: font,
                    styleChangedByUser: nil, fillColor: nil)
            }
            canvas.selectAndEdit(node.id)
            guard let editor = canvas.subviews.compactMap({ $0 as? NSTextField }).first else {
                fatalError("Expected a live title editor")
            }
            return editor.alignment
        }
        let child = MapNode(id: UUID(), title: "Branch", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "Main topic", children: [child], folded: false)
        assert(editorAlignment(root: root) == .center,
               "New main topic title defaults to center alignment in both editor and paint")
        assert(editorAlignment(root: root, child: true) == .left,
               "Unstyled subnode title retains its left alignment")
        var explicitlyLeft = root
        explicitlyLeft.textAlignment = "left"
        assert(editorAlignment(root: explicitlyLeft) == .left,
               "A user's saved explicit left alignment must override the default")
        assert(editorAlignment(root: root, imported: "right") == .right,
               "A read-only MindNode import's explicit text alignment is preserved")
        print("root default center, subnode default left and explicit/imported overrides passed")
    }
}
