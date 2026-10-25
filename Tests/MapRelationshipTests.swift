import AppKit

@main
enum MapRelationshipTests {
    static func main() throws {
        let root = UUID(), left = UUID(), right = UUID(), copiedLeft = UUID(), copiedRight = UUID()
        let edge = MapRelationship(id: UUID(), from: left, to: right,
            control1: SIMD2(40, 30), control2: SIMD2(-40, -30),
            style: .dashed, startArrow: true, endArrow: true)
        let ids: Set<UUID> = [root, left, right]
        assert(validRelationship(edge, nodeIDs: ids))
        let from = CGPoint(x: 100, y: 200), to = CGPoint(x: 300, y: 100)
        let geometry = relationshipGeometry(edge, from: from, to: to)!
        assert(geometry.control1 == CGPoint(x: 140, y: 230))
        assert(geometry.control2 == CGPoint(x: 260, y: 70))
        assert(geometry.path.elementCount == 2, "One actual cubic curve, not a straight tree connector")
        var curvePoints = [CGPoint](repeating: .zero, count: 3)
        let element = geometry.path.element(at: 1, associatedPoints: &curvePoints)
        assert(element == .cubicCurveTo && curvePoints == [geometry.control1, geometry.control2, to])
        assert(geometry.startArrowhead?.count == 3 && geometry.endArrowhead?.count == 3)
        assert(geometry.startArrowhead?.first == from && geometry.endArrowhead?.first == to)
        assert(geometry.startArrowhead![1].x > from.x && geometry.startArrowhead![2].x > from.x &&
               geometry.endArrowhead![1].x < to.x && geometry.endArrowhead![2].x < to.x,
               "Both arrow wings point back toward their own endpoint tangent")
        var moved = edge
        moved.control1 = SIMD2(80, -20)
        assert(relationshipGeometry(moved, from: from, to: to)!.control1 == CGPoint(x: 180, y: 180))
        assert(relationshipGeometry(moved, from: from, to: to)!.control2 == geometry.control2)
        let upper = CGRect(x: 100, y: 100, width: 120, height: 60)
        let lower = CGRect(x: 100, y: 400, width: 120, height: 60)
        let vertical = relationshipGeometry(MapRelationship(from: left, to: right), from: upper, to: lower)!
        assert(vertical.start.y == upper.maxY && vertical.end.y == lower.minY,
               "Vertical relationships must start/end on the nearest node outline, not a fixed left/right side")
        assert((upper.minX...upper.maxX).contains(vertical.start.x) &&
               (lower.minX...lower.maxX).contains(vertical.end.x) &&
               vertical.endArrowhead?.first == vertical.end,
               "Arrow tips must remain on the same node boundary as the curve")
        let reversed = relationshipGeometry(MapRelationship(from: left, to: right), from: lower, to: upper)!
        assert(reversed.start.y == lower.minY && reversed.end.y == upper.maxY,
               "Moving a node past the other must slide both anchors to the newly nearest sides")
        let horizontal = CGRect(x: 400, y: 100, width: 120, height: 60)
        let straight = relationshipGeometry(MapRelationship(from: left, to: right), from: upper, to: horizontal)!
        var upward = MapRelationship(from: left, to: right)
        upward.control1 = SIMD2(0, -1_000)
        upward.control2 = SIMD2(0, 1_000)
        let aimed = relationshipGeometry(upward, from: upper, to: horizontal)!
        assert(straight.start.x == upper.maxX && straight.end.x == horizontal.minX &&
               aimed.start.y == upper.minY && aimed.end.y == horizontal.maxY,
               "Dragging either Bézier control past a node corner slides its arrow anchor onto the facing edge")
        let decoded = try JSONDecoder().decode(MapRelationship.self, from: JSONEncoder().encode(edge))
        assert(decoded == edge)
        var manuallyAimed = edge
        manuallyAimed.control1Aim = SIMD2(-250, 20)
        manuallyAimed.control2Aim = SIMD2(300, -80)
        let manualBytes = try JSONEncoder().encode(manuallyAimed)
        let restoredManual = try JSONDecoder().decode(MapRelationship.self, from: manualBytes)
        assert(restoredManual == manuallyAimed,
               "World-center aims from dragged handles must survive own JSON save and reopen")
        manuallyAimed.control1Aim = SIMD2(.nan, 0)
        assert(!validRelationship(manuallyAimed, nodeIDs: ids),
               "Untrusted JSON must not introduce nonfinite manual Bézier anchor directions")
        var dotted = edge
        dotted.style = .dotted
        let decodedDot = try JSONDecoder().decode(MapRelationship.self, from: JSONEncoder().encode(dotted))
        assert(decodedDot == dotted)
        var noArrows = edge
        noArrows.startArrow = false
        noArrows.endArrow = false
        let bare = relationshipGeometry(noArrows, from: from, to: to)!
        assert(bare.startArrowhead == nil && bare.endArrowhead == nil)
        var invalid = edge
        invalid.to = UUID()
        assert(!validRelationship(invalid, nodeIDs: ids), "Dangling node cannot be connected")
        invalid.to = left
        assert(!validRelationship(invalid, nodeIDs: ids), "Self-loop is not a cross-node relation")
        invalid.to = right
        invalid.control1 = SIMD2(.nan, 0)
        assert(!validRelationship(invalid, nodeIDs: ids))
        assert(relationshipGeometry(invalid, from: from, to: to) == nil)
        invalid.control1 = SIMD2(1_000_001, 0)
        assert(!validRelationship(invalid, nodeIDs: ids))
        assert(relationshipGeometry(edge, from: CGPoint(x: CGFloat.infinity, y: 0), to: to) == nil)
        assert(sanitizeRelationships([edge, edge, invalid], nodeIDs: ids) == [edge],
               "Keep first valid relation ID and reject duplicates/nonfinite controls")
        let remapped = remapRelationships([edge, invalid], nodeIDs: [left: copiedLeft, right: copiedRight])
        assert(remapped.count == 1 && remapped[0].id != edge.id &&
               remapped[0].from == copiedLeft && remapped[0].to == copiedRight)
        assert(remapRelationships([edge, edge], nodeIDs: [left: copiedLeft, right: copiedRight]).count == 1,
               "Duplicate source relationship IDs cannot fork into distinct copied edges")
        assert(remapRelationships([edge], nodeIDs: [left: copiedLeft]).isEmpty,
               "Copying one endpoint must not leave a dangling cloned relationship")
        let legacy = "[{\"id\":\"\(root)\",\"title\":\"旧图\",\"folded\":false,\"children\":[]}]".data(using: .utf8)!
        let oldRoots = try JSONDecoder().decode([MapNode].self, from: legacy)
        assert(oldRoots[0].id == root && sanitizeRelationships([], nodeIDs: [root]).isEmpty)
        print("relationship data, cubic geometry, arrowheads and copy remapping tests passed")
    }
}
