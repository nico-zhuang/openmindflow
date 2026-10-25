import AppKit

@main enum MapClipboardTests {
    static func main() throws {
        let grandchild = MapNode(id: UUID(), title: "grandchild", children: [], folded: false,
                                 location: SIMD2(440, 190))
        let child = MapNode(id: UUID(), title: "child", children: [grandchild], folded: false,
                            location: SIMD2(300, 170))
        let root = MapNode(id: UUID(), title: "root", children: [child], folded: false,
                           location: SIMD2(120, 150))
        let outside = MapNode(id: UUID(), title: "outside", children: [], folded: false,
                              location: SIMD2(620, 130))
        let insideLink = MapRelationship(id: UUID(), from: root.id, to: grandchild.id,
                                         control1: SIMD2(80, -20), control2: SIMD2(-70, 30),
                                         style: .dashed, startArrow: true, endArrow: true)
        let outsideLink = MapRelationship(id: UUID(), from: child.id, to: outside.id,
                                          control1: SIMD2(80, 0), control2: SIMD2(-80, 0),
                                          style: .solid, startArrow: false, endArrow: false)
        let model = MapModel(roots: [root, outside], selected: root.id)
        model.relationships = [insideLink, outsideLink]
        assert(model.selectNodes([root.id, child.id]), "Parent and child must both be selected")
        let original = model.roots, originalEdges = model.relationships
        let group = try XCTUnwrap(model.copySelection(), "Cannot copy selected branch")
        assert(group.roots.count == 1 && group.roots[0].children[0].children[0].title == "grandchild",
               "Copying parent and child must not clone child twice and must include full descendants")
        assert(group.relationships.map(\.id) == [insideLink.id], "Copy only relationships internal to branch")
        assert(model.pasteSelection(group, at: CGPoint(x: 900, y: 600)), "Blank paste must add a whole branch")
        assert(model.roots.count == 3 && model.roots[0...1] == original[0...1], "Original roots remain unchanged")
        let pasted = model.roots[2]
        assert(pasted.title == root.title && pasted.id != root.id && pasted.children[0].id != child.id
               && pasted.children[0].children[0].id != grandchild.id, "Every copied node gets a new ID")
        assert(pasted.location == SIMD2(900, 600) && pasted.children[0].location == SIMD2(1080, 620),
               "A group lands at the blank anchor preserving child displacement")
        assert(model.selectedIDs == [pasted.id], "Pasted top-level group is selected")
        assert(model.relationships.count == 3 && model.relationships[2].id != insideLink.id
               && model.relationships[2].from == pasted.id
               && model.relationships[2].to == pasted.children[0].children[0].id,
               "Internal relationship IDs and endpoints remap to cloned nodes")
        assert(model.undo() && model.roots == original && model.relationships == originalEdges,
               "One Undo restores both tree and relationships")
        assert(model.redo() && model.roots.count == 3 && model.relationships.count == 3,
               "One Redo restores both")
        assert(model.pasteSelection(group, at: CGPoint(x: 1000, y: 700)), "Same clipboard can paste again")
        assert(Set(model.roots.map(\.id)).count == 4 && model.relationships[3].id != model.relationships[2].id,
               "Repeated paste uses distinct IDs")
        let malformed = MapSelectionClip(roots: [root, root], relationships: [])
        let before = model.roots, edgesBefore = model.relationships
        assert(!model.pasteSelection(malformed, at: CGPoint(x: 0, y: 0))
               && model.roots == before && model.relationships == edgesBefore,
               "Malformed external clipboard must not change tree, edges, or Undo")
        var orphanVideoWidth = root
        orphanVideoWidth.videoWidth = 200
        assert(!model.pasteSelection(MapSelectionClip(roots: [orphanVideoWidth], relationships: []),
                                     at: CGPoint(x: 1100, y: 800)) && model.roots == before,
               "Untrusted clipboard must reject orphan video metadata just like document decoding")
        print("whole-branch clipboard remap, anchor and Undo passed")
    }
}

private func XCTUnwrap<T>(_ value: T?, _ failure: String) throws -> T {
    guard let value else { throw NSError(domain: failure, code: 1) }
    return value
}
