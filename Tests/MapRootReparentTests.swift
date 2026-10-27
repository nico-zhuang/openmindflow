import AppKit

@main enum MapRootReparentTests {
    static func main() {
        let oldLeaf = MapNode(id: UUID(), title: "Former first level", children: [], folded: false,
                              location: SIMD2(890, 320), branchSide: "left")
        var media = MapNode(id: UUID(), title: "Pasted image", children: [oldLeaf], folded: false,
                            location: SIMD2(800, 320))
        media.rootShape = "rounded"
        media.rootFillColor = "#123456FF"
        let destination = MapNode(id: UUID(), title: "Attach here", children: [], folded: false)
        let base = MapNode(id: UUID(), title: "Main", children: [destination], folded: false,
                           location: SIMD2(170, 220))
        let model = MapModel(roots: [base, media], selected: media.id)
        let before = model.roots
        assert(model.canMoveNode(media.id, to: destination.id, at: 0),
               "A previously independent pasted root can be attached to an existing child")
        assert(model.moveNode(media.id, to: destination.id, at: 0),
               "Root-to-child drag must commit one atomic model move")
        guard model.roots.count == 1, model.roots[0].children[0].children.map(\.id) == [media.id] else {
            fatalError("Media root must no longer float as an independent top-level node")
        }
        let attached = model.roots[0].children[0].children[0]
        assert(attached.location == nil && attached.rootShape == nil && attached.rootFillColor == nil &&
               attached.children[0].location == nil && attached.children[0].branchSide == nil,
               "A former root must lose absolute positions and root-only appearance before child layout")
        let boxes = Dictionary(uniqueKeysWithValues: mapLayout(model.roots).map { ($0.node.id, $0.frame) })
        assert(!boxes[media.id]!.intersects(boxes[destination.id]!) &&
               !boxes[oldLeaf.id]!.intersects(boxes[destination.id]!),
               "Committing a root attach cannot leave old coordinates obscuring the target")
        assert(model.undo() && model.roots == before && model.selectedIDs == [media.id],
               "One Undo restores the floating root with its original coordinates and style")
        assert(!model.undo(), "Reparenting a root is exactly one Undo step")
        print("independent root attaches to child without stale coordinates or occlusion; Undo passed")
    }
}
