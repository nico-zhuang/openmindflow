import AppKit

@main enum MapDocumentBudgetTests {
    static func main() throws {
        let root = MapNode(id: UUID(), title: "", children: [], folded: false)
        let peer = MapNode(id: UUID(), title: "peer", children: [], folded: false)
        let overhead = try JSONEncoder().encode([root, peer]).count
        var full = root
        full.title = String(repeating: "x", count: MapModel.maxSavedJSONBytes - overhead - 16)
        let model = MapModel(roots: [full, peer], selected: full.id)
        let edge = MapRelationship(from: full.id, to: peer.id)
        let rootBytes = try JSONEncoder().encode(model.roots).count
        let documentBytes = try JSONEncoder().encode(OwnMapDocument(roots: model.roots, relationships: [edge])).count
        assert(rootBytes < MapModel.maxSavedJSONBytes,
               "Legacy roots fit just below the 32 MiB saved-document boundary")
        assert(documentBytes > MapModel.maxSavedJSONBytes,
               "Adding a relationship crosses the *exact* new envelope budget")
        assert(!model.setRelationship(edge) && model.relationships.isEmpty,
               "Reject unsavable relationship before modifying model or Undo")
        let originalRoots = model.roots
        let oversizedTitle = full.title + String(repeating: "y", count: 64)
        var renamed = originalRoots
        renamed[0].title = oversizedTitle
        let renamedBytes = try JSONEncoder().encode(renamed).count
        assert(renamedBytes > MapModel.maxSavedJSONBytes)
        model.rename(oversizedTitle)
        assert(model.roots == originalRoots && !model.undo(),
               "Reject oversized rename before changing roots or creating Undo")
        let positioned = MapModel(roots: originalRoots, selected: full.id)
        var moved = originalRoots
        moved[0].location = SIMD2(1_000_000, 1_000_000)
        let movedBytes = try JSONEncoder().encode(moved).count
        assert(movedBytes > MapModel.maxSavedJSONBytes)
        assert(!positioned.translateSelectedSubtrees(by: CGPoint(x: 1, y: 1),
                                                       visibleCenters: [full.id: CGPoint(x: 999_999, y: 999_999)]))
        assert(positioned.roots == originalRoots && positioned.selected == full.id && !positioned.undo(),
               "Reject coordinate growth before changing roots, selection or Undo")
        let main = MapModel(roots: originalRoots, selected: full.id)
        main.addMainNode()
        assert(main.roots == originalRoots && main.selected == full.id && main.selectedIDs == [full.id] && !main.undo(),
               "Reject a new main node before changing roots, selection or Undo")
        let child = MapNode(id: UUID(), title: "child", children: [], folded: false)
        let destination = MapNode(id: UUID(), title: "destination", children: [], folded: false)
        var branch = MapNode(id: UUID(), title: "", children: [child, destination], folded: false)
        let branchOverhead = try JSONEncoder().encode([branch]).count
        branch.title = String(repeating: "x", count: MapModel.maxSavedJSONBytes - branchOverhead - 16)
        let branchRoots = [branch]
        let candidate = MapModel(roots: branchRoots, selected: child.id)
        candidate.addChild()
        candidate.addSibling()
        candidate.addParent()
        assert(candidate.roots == branchRoots && candidate.selected == child.id && candidate.selectedIDs == [child.id] && !candidate.undo(),
               "Reject every nested insertion without changing roots, selection or Undo")
        assert(!candidate.moveNode(child.id, to: destination.id, at: 0,
                                   location: CGPoint(x: 1_000_000, y: 1_000_000)))
        assert(!candidate.moveSelectedNodes(to: destination.id, at: 0,
                                            locations: [child.id: CGPoint(x: 1_000_000, y: 1_000_000)]))
        assert(!candidate.arrange(at: [branch.id: CGPoint(x: 1_000_000, y: 1_000_000),
                                       child.id: CGPoint(x: 0, y: 0), destination.id: CGPoint(x: 0, y: 0)]))
        assert(candidate.roots == branchRoots && candidate.selected == child.id && !candidate.undo(),
               "Reject reparenting and arranging when saved coordinates exceed the limit")
        var folded = MapNode(id: UUID(), title: "", children: [child], folded: true)
        let foldedOverhead = try JSONEncoder().encode([folded]).count
        folded.title = String(repeating: "x", count: MapModel.maxSavedJSONBytes - foldedOverhead)
        let foldedRoots = [folded]
        var unfolded = folded
        unfolded.folded = false
        let foldedBytes = try JSONEncoder().encode(foldedRoots).count
        let unfoldedBytes = try JSONEncoder().encode([unfolded]).count
        assert(foldedBytes == MapModel.maxSavedJSONBytes && unfoldedBytes > MapModel.maxSavedJSONBytes)
        let fold = MapModel(roots: foldedRoots, selected: folded.id)
        assert(!fold.toggleFold() && fold.roots == foldedRoots && fold.selected == folded.id && !fold.undo(),
               "Changing folded=true to false grows the JSON boolean by one byte")
        let reveal = MapModel(roots: foldedRoots, selected: folded.id)
        assert(!reveal.revealSearchResult(child.id) && reveal.roots == foldedRoots &&
               reveal.selected == folded.id && !reveal.undo(),
               "Rejected reveal must not alter the previously selected node")
        print("exact combined roots-and-relationships JSON capacity check passed")
    }
}
