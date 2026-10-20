import Foundation
import CoreGraphics

struct LaidOutNode {
    let node: MapNode
    let frame: CGRect
    let parent: UUID?
}

func dropPlacement(at point: CGPoint, over node: LaidOutNode,
                   siblings: [LaidOutNode]) -> (parent: UUID, index: Int)? {
    guard node.frame.contains(point) else { return nil }
    let fraction = (point.y - node.frame.minY) / node.frame.height
    if fraction < 0.25 || fraction > 0.75 {
        guard let parent = node.parent,
              let index = siblings.firstIndex(where: { $0.node.id == node.node.id }) else { return nil }
        // ponytail: quarter-height drop zones; measure original hit areas before tuning.
        return (parent, index + (fraction > 0.75 ? 1 : 0))
    }
    return (node.node.id, node.node.children.count)
}

func mapLayout(_ roots: [MapNode]) -> [LaidOutNode] {
    var result: [LaidOutNode] = []
    var row = 0

    @discardableResult
    func place(_ node: MapNode, depth: Int, parent: UUID?) -> CGFloat {
        let y: CGFloat
        let index = result.count
        result.append(LaidOutNode(node: node, frame: .zero, parent: parent))
        if node.folded || node.children.isEmpty {
            y = CGFloat(row) * 76
            row += 1
        } else {
            let childRows = node.children.map { place($0, depth: depth + 1, parent: node.id) }
            y = (childRows[0] + childRows[childRows.count - 1]) / 2
        }
        result[index] = LaidOutNode(node: node,
                                    frame: CGRect(x: CGFloat(depth) * 230, y: y, width: 170, height: 44),
                                    parent: parent)
        return y
    }

    for root in roots { place(root, depth: 0, parent: nil) }
    return result
}
