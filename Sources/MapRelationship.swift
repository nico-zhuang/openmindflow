import AppKit

enum MapRelationshipStyle: String, Codable { case solid, dashed, dotted }

struct MapRelationship: Codable, Equatable {
    var id: UUID
    var from: UUID
    var to: UUID
    var control1: SIMD2<Double> // World-space offset from the start node anchor.
    var control2: SIMD2<Double> // World-space offset from the end node anchor.
    var control1Aim: SIMD2<Double>? // Manually aimed handle, relative to start node center.
    var control2Aim: SIMD2<Double>? // Manually aimed handle, relative to end node center.
    var style: MapRelationshipStyle
    var startArrow: Bool
    var endArrow: Bool

    init(id: UUID = UUID(), from: UUID, to: UUID,
         control1: SIMD2<Double> = SIMD2(60, 0), control2: SIMD2<Double> = SIMD2(-60, 0),
         style: MapRelationshipStyle = .solid, startArrow: Bool = false, endArrow: Bool = true) {
        self.id = id
        self.from = from
        self.to = to
        self.control1 = control1
        self.control2 = control2
        self.control1Aim = nil
        self.control2Aim = nil
        self.style = style
        self.startArrow = startArrow
        self.endArrow = endArrow
    }
}

func validRelationship(_ edge: MapRelationship, nodeIDs: Set<UUID>) -> Bool {
    nodeIDs.contains(edge.from) && nodeIDs.contains(edge.to) && edge.from != edge.to &&
        ([edge.control1.x, edge.control1.y, edge.control2.x, edge.control2.y] +
         [edge.control1Aim?.x, edge.control1Aim?.y, edge.control2Aim?.x, edge.control2Aim?.y].compactMap { $0 })
            .allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
}

func sanitizeRelationships(_ edges: [MapRelationship], nodeIDs: Set<UUID>) -> [MapRelationship] {
    var seen = Set<UUID>()
    return edges.filter { validRelationship($0, nodeIDs: nodeIDs) && seen.insert($0.id).inserted }
}

func remapRelationships(_ edges: [MapRelationship], nodeIDs: [UUID: UUID]) -> [MapRelationship] {
    let originals = sanitizeRelationships(edges, nodeIDs: Set(nodeIDs.keys))
    return originals.compactMap { edge in
        guard let from = nodeIDs[edge.from], let to = nodeIDs[edge.to], from != to else { return nil }
        var copy = edge
        copy.id = UUID()
        copy.from = from
        copy.to = to
        return copy
    }
}

struct RelationshipGeometry {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
    let startArrowhead: [CGPoint]?
    let endArrowhead: [CGPoint]?

    var path: NSBezierPath {
        let curve = NSBezierPath()
        curve.move(to: start)
        curve.curve(to: end, controlPoint1: control1, controlPoint2: control2)
        return curve
    }
}

func relationshipAnchor(in node: CGRect, toward target: CGPoint) -> CGPoint? {
    guard node.width > 0, node.height > 0,
          [node.minX, node.minY, node.maxX, node.maxY, target.x, target.y].allSatisfy(\.isFinite) else { return nil }
    let dx = target.x - node.midX, dy = target.y - node.midY
    guard dx != 0 || dy != 0 else { return nil }
    let scale = min(dx == 0 ? .infinity : node.width / (2 * abs(dx)),
                    dy == 0 ? .infinity : node.height / (2 * abs(dy)))
    return CGPoint(x: node.midX + dx * scale, y: node.midY + dy * scale)
}

func relationshipGeometry(_ edge: MapRelationship, from source: CGRect, to target: CGRect) -> RelationshipGeometry? {
    guard validRelationship(edge, nodeIDs: [edge.from, edge.to]) else { return nil }
    let startAim = edge.control1Aim.flatMap { $0 == .zero ? nil : CGPoint(
        x: source.midX + $0.x, y: source.midY + $0.y) }
        ?? CGPoint(x: target.midX + edge.control1.x, y: target.midY + edge.control1.y)
    let endAim = edge.control2Aim.flatMap { $0 == .zero ? nil : CGPoint(
        x: target.midX + $0.x, y: target.midY + $0.y) }
        ?? CGPoint(x: source.midX + edge.control2.x, y: source.midY + edge.control2.y)
    guard let start = relationshipAnchor(in: source, toward: startAim),
          let end = relationshipAnchor(in: target, toward: endAim) else { return nil }
    return relationshipGeometry(edge, from: start, to: end)
}

func relationshipGeometry(_ edge: MapRelationship, from: CGPoint, to: CGPoint) -> RelationshipGeometry? {
    guard validRelationship(edge, nodeIDs: [edge.from, edge.to]), from != to else { return nil }
    let c1 = CGPoint(x: from.x + edge.control1.x, y: from.y + edge.control1.y)
    let c2 = CGPoint(x: to.x + edge.control2.x, y: to.y + edge.control2.y)
    guard [from.x, from.y, to.x, to.y, c1.x, c1.y, c2.x, c2.y].allSatisfy({
        $0.isFinite && abs($0) <= 1_000_000
    }) else { return nil }
    func head(tip: CGPoint, toward: CGPoint) -> [CGPoint] {
        let dx = toward.x - tip.x, dy = toward.y - tip.y
        let length = hypot(dx, dy)
        let ux = dx / length, uy = dy / length
        let base = CGPoint(x: tip.x + ux * 12, y: tip.y + uy * 12)
        return [tip, CGPoint(x: base.x - uy * 5, y: base.y + ux * 5),
                CGPoint(x: base.x + uy * 5, y: base.y - ux * 5)]
    }
    return RelationshipGeometry(start: from, control1: c1, control2: c2, end: to,
        startArrowhead: edge.startArrow ? head(tip: from, toward: c1 == from ? to : c1) : nil,
        endArrowhead: edge.endArrow ? head(tip: to, toward: c2 == to ? from : c2) : nil)
}
