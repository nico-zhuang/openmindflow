import AppKit

@main enum LeftBranchModelTests {
    static func main() throws {
        let leaf = MapNode(id: UUID(), title: "leaf", children: [], folded: false,
                           location: SIMD2(-500, 40), note: "keep note")
        let left = MapNode(id: UUID(), title: "left", children: [leaf], folded: false,
                           location: SIMD2(-300, 20))
        let right = MapNode(id: UUID(), title: "right", children: [], folded: false,
                            location: SIMD2(300, 20))
        let root = MapNode(id: UUID(), title: "root", children: [left, right], folded: false,
                           location: SIMD2(0, 0))
        let model = MapModel(roots: [root], selected: root.id)
        let edge = MapRelationship(from: left.id, to: right.id)
        model.relationships = [edge]
        assert(!model.setRootBranchSide("left", for: root.id))
        assert(!model.setRootBranchSide("left", for: leaf.id))
        assert(!model.setRootBranchSide("LEFT", for: left.id))
        assert(!model.setRootBranchSide("left", for: UUID()))
        assert(!model.undo(), "Rejected calls cannot create history")
        assert(model.setRootBranchSide("right", for: left.id), "nil to explicit right is deliberate")
        assert(model.roots[0].children[0].branchSide == "right")
        assert(model.roots[0].children[0].location == nil && model.roots[0].children[0].children[0].location == nil)
        assert(model.roots[0].location == root.location && model.roots[0].children[1] == right)
        assert(model.relationships == [edge] && model.roots[0].children[0].children[0].note == "keep note")
        assert(!model.setRootBranchSide("right", for: left.id))
        assert(model.undo() && model.roots == [root] && model.relationships == [edge])
        assert(!model.undo(), "A side switch has exactly one undo entry")
        assert(model.redo() && model.roots[0].children[0].branchSide == "right")
        assert(model.setRootBranchSide("left", for: left.id))
        assert(model.roots[0].children[0].branchSide == "left")
        assert(model.undo() && model.roots[0].children[0].branchSide == "right")

        let legacy = try JSONEncoder().encode([root])
        let legacyDecoded = try JSONDecoder().decode([MapNode].self, from: legacy)
        assert(legacyDecoded[0].children[0].branchSide == nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("left-branch-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("branch.mindmap.json")
        var styled = root
        styled.children[0].branchSide = "left"
        styled.children[1].branchSide = "right"
        try writeOwnJSON([styled], to: url)
        let arrayReopened = try readOwnJSON(url)
        let arrayBytes = try Data(contentsOf: url)
        assert(arrayReopened == [styled] && arrayBytes.first == UInt8(ascii: "["))
        try writeOwnDocument(OwnMapDocument(roots: [styled], relationships: [edge]), to: url)
        let reopened = try readOwnDocument(url)
        assert(reopened.roots == [styled] && reopened.relationships == [edge])
        let objectBytes = try Data(contentsOf: url)
        assert(objectBytes.first == UInt8(ascii: "{"))
        func invalidStyle(_ roots: [MapNode]) {
            do { _ = try checkOwnJSONNodes(roots); fatalError("Expected invalidStyle") }
            catch OwnJSONError.invalidStyle { }
            catch { fatalError("Unexpected error: \(error)") }
        }
        var invalid = styled
        invalid.branchSide = "left"
        invalidStyle([invalid])
        invalid = styled
        invalid.children[0].children[0].branchSide = "left"
        invalidStyle([invalid])
        for side in ["", "LEFT", "middle"] {
            invalid = styled
            invalid.children[0].branchSide = side
            invalidStyle([invalid])
            do { try writeOwnDocument(OwnMapDocument(roots: [invalid], relationships: [edge]), to: url); fatalError("Expected invalidStyle") }
            catch OwnJSONError.invalidStyle { }
        }
        let unchanged = try readOwnDocument(url)
        assert(unchanged.roots == [styled], "Invalid writes leave existing file intact")

        let edits = MapModel(roots: [styled], selected: left.id)
        edits.addSibling()
        assert(edits.roots[0].children[1].branchSide == "left")
        edits.selected = left.id
        edits.addParent()
        let newParent = edits.roots[0].children[0]
        assert(newParent.branchSide == "left" && newParent.children[0].branchSide == nil)
        assert(edits.undo() && edits.roots[0].children[0].branchSide == "left")
        let clip = try unwrap(edits.copySelection())
        assert(edits.pasteSelection(clip, at: CGPoint(x: 700, y: 200)))
        assert(edits.roots.last?.branchSide == nil && edits.roots.last?.children[0].branchSide == nil)
        let pastedIDs = try checkOwnJSONNodes(edits.roots)
        assert(pastedIDs.count == 7)
        assert(edits.undo() && edits.roots.count == 1)
        assert(edits.detachSelected())
        assert(edits.roots[1].branchSide == nil && edits.roots[1].children[0].branchSide == nil)
        assert(edits.undo())
        assert(edits.moveNode(left.id, to: right.id, at: 0))
        assert(edits.roots[0].children[1].children[0].branchSide == nil)
        assert(edits.undo())
        assert(edits.moveNode(left.id, to: root.id, at: 2))
        assert(edits.roots[0].children[1].branchSide == "left")
        assert(edits.undo())
        assert(edits.moveSelectedNodes(to: right.id, at: 0))
        assert(edits.roots[0].children[1].children[0].branchSide == nil)
        assert(edits.undo())
        let finalIDs = try checkOwnJSONNodes(edits.roots)
        assert(finalIDs.count == 5)
        print("left branch model, strict JSON, structural edits and undo passed")
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "missing clipboard", code: 1) }
        return value
    }
}
