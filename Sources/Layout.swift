import Foundation
import CoreGraphics

struct LaidOutNode {
    let node: MapNode
    let frame: CGRect
    let parent: UUID?
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
