import AppKit

@main enum MapRelationshipModelTests {
    static func main() {
        let child = MapNode(id: UUID(), title: "child", children: [], folded: false)
        let root = MapNode(id: UUID(), title: "root", children: [child], folded: false)
        let peer = MapNode(id: UUID(), title: "peer", children: [], folded: false)
        let model = MapModel(roots: [root, peer], selected: root.id)
        let edge = MapRelationship(from: child.id, to: peer.id)
        assert(model.setRelationship(edge) && model.relationships == [edge], "Adding a cross-node edge changes model")
        assert(!model.setRelationship(edge), "No-op relation must not create extra Undo")
        var curved = edge
        curved.control1 = SIMD2(83, 46)
        curved.style = .dotted
        curved.startArrow = true
        assert(model.setRelationship(curved) && model.relationships == [curved],
               "Editing curve geometry and style persists together")
        assert(model.undo() && model.relationships == [edge], "One Undo restores the previous curve")
        assert(model.redo() && model.relationships == [curved], "One Redo restores the edit")
        model.selected = child.id
        assert(model.remove() && model.relationships.isEmpty, "Deleting a node removes dangling cross-node edges")
        assert(model.undo() && model.relationships == [curved] && model.roots[0].children == [child],
               "Node deletion and edge cleanup undo atomically")
        assert(model.removeRelationship(curved.id) && model.relationships.isEmpty, "One edge can be deleted")
        assert(model.undo() && model.relationships == [curved], "Edge deletion is undoable")
        let unknown = MapRelationship(from: UUID(), to: root.id)
        assert(!model.setRelationship(unknown) && model.relationships == [curved],
               "Invalid endpoints must not change model or clear redo history")
        print("relationship model edit, node deletion and atomic Undo passed")
    }
}
