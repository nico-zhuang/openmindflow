import AppKit

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

func mapFont(isRoot: Bool, zoom: CGFloat = 1) -> NSFont {
    NSFont.systemFont(ofSize: (isRoot ? 16 : 14) * zoom, weight: isRoot ? .semibold : .medium)
}

func mapLayout(_ roots: [MapNode]) -> [LaidOutNode] {
    let gap: CGFloat = 32
    var sizes: [UUID: CGSize] = [:]
    var subtreeHeights: [UUID: CGFloat] = [:]
    var columnWidths: [CGFloat] = []

    @discardableResult
    func measure(_ node: MapNode, depth: Int) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: mapFont(isRoot: depth == 0)]
        let title = node.title.isEmpty ? "New idea" : node.title
        let text = (node.folded && !node.children.isEmpty ? "▸ " : "") + title
        let longestLine = text.components(separatedBy: "\n").map {
            ($0 as NSString).size(withAttributes: attributes).width
        }.max() ?? 0
        // ponytail: 320pt maximum wraps long labels; expose a width preference if users need denser maps.
        let width = min(320, max(170, ceil(longestLine) + 24))
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width - 24, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        let height = max(44, ceil(bounds.height) + 22)
        sizes[node.id] = CGSize(width: width, height: height)
        if depth == columnWidths.count { columnWidths.append(width) }
        else { columnWidths[depth] = max(columnWidths[depth], width) }
        let children = node.folded ? [] : node.children
        let childHeight = children.map { measure($0, depth: depth + 1) }.reduce(0, +)
            + CGFloat(max(0, children.count - 1)) * gap
        let subtreeHeight = max(height, childHeight)
        subtreeHeights[node.id] = subtreeHeight
        return subtreeHeight
    }
    let rootHeights = roots.map { measure($0, depth: 0) }
    var columnX: [CGFloat] = []
    var x: CGFloat = 0
    for width in columnWidths {
        columnX.append(x)
        x += width + 60
    }
    var result: [LaidOutNode] = []
    func place(_ node: MapNode, depth: Int, parent: UUID?, top: CGFloat) {
        let size = sizes[node.id]!
        let subtreeHeight = subtreeHeights[node.id]!
        let frame = CGRect(x: columnX[depth], y: top + (subtreeHeight - size.height) / 2,
                           width: size.width, height: size.height)
        result.append(LaidOutNode(node: node, frame: frame, parent: parent))
        let children = node.folded ? [] : node.children
        let childHeight = children.reduce(CGFloat(0)) { $0 + subtreeHeights[$1.id]! }
            + CGFloat(max(0, children.count - 1)) * gap
        var childTop = top + (subtreeHeight - childHeight) / 2
        for child in children {
            place(child, depth: depth + 1, parent: node.id, top: childTop)
            childTop += subtreeHeights[child.id]! + gap
        }
    }
    var top: CGFloat = 0
    for (root, height) in zip(roots, rootHeights) {
        place(root, depth: 0, parent: nil, top: top)
        top += height + gap
    }
    return result
}
