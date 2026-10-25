import AppKit

@main enum MapDocumentBudgetTests {
    static func main() throws {
        let root = MapNode(id: UUID(), title: "", children: [], folded: false)
        let peer = MapNode(id: UUID(), title: "peer", children: [], folded: false)
        let overhead = try JSONEncoder().encode([root, peer]).count
        var full = root
        full.title = String(repeating: "x", count: MapModel.maxSavedJSONBytes - overhead - 32)
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
        print("exact combined roots-and-relationships JSON capacity check passed")
    }
}
