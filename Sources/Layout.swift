import AppKit

struct LaidOutNode {
    let node: MapNode
    let frame: CGRect
    let parent: UUID?
}

struct MapLayoutOverride {
    let location: CGPoint?
    let maxWidth: CGFloat?
    let allowToShrinkWidth: Bool
    let font: NSFont?
}

#if HEADLESS_TEST
var mapLayoutInvocations = 0
#endif

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

func mapFont(isRoot: Bool, zoom: CGFloat = 1, node: MapNode? = nil) -> NSFont {
    let size: CGFloat = CGFloat(node?.fontSize ?? (isRoot ? 24 : 20)) * zoom
    return node?.fontFamily.flatMap { NSFont(name: $0, size: size) }
        ?? NSFont(name: "STSongti-SC-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
}

func mapNodeSize(_ node: MapNode, font: NSFont, isRoot: Bool,
                 maxWidth: CGFloat? = nil, allowToShrinkWidth: Bool = false) -> CGSize {
    let hasMedia = node.image != nil || node.video != nil
    let title = node.title.isEmpty && hasMedia ? "" : (node.title.isEmpty ? "New idea" : node.title)
    let text = (node.folded && !node.children.isEmpty ? "▸ " : "") + title
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let longestLine = text.components(separatedBy: "\n").map {
        ($0 as NSString).size(withAttributes: attributes).width
    }.max() ?? 0
    let naturalWidth = max(ceil(longestLine) + 24,
                           node.image.map { $0.displaySize(width: node.imageWidth).width + 24 } ?? 0,
                           node.video.map { $0.displaySize(width: node.videoWidth).width + 24 } ?? 0)
    let width: CGFloat
    if let explicit = node.width { width = explicit }
    else if let maxWidth {
        width = max(60, allowToShrinkWidth ? min(naturalWidth, maxWidth) : maxWidth)
    } else { width = min(hasMedia ? 1000 : 320, max(170, naturalWidth)) }
    // Root renderer reserves 24pt beside the usual 24pt title inset for its note paper.
    let noteSpace: CGFloat = isRoot && node.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 24 : 0
    let textHeight: CGFloat = text.isEmpty ? 0 : ceil((text as NSString).boundingRect(
        with: CGSize(width: max(1, width - 24 - noteSpace), height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).height)
    let imageHeight = node.image.map {
        ceil($0.displaySize(width: min(node.imageWidth ?? $0.displaySize().width, max(1, width - 24))).height)
    } ?? 0
    let videoHeight = node.video.map {
        ceil($0.displaySize(width: min(node.videoWidth ?? $0.displaySize().width, max(1, width - 24))).height)
    } ?? 0
    return CGSize(width: width, height: max(44, max(imageHeight, videoHeight) + textHeight
        + 22 + (hasMedia && !text.isEmpty ? 8 : 0)))
}

func mapLayout(_ roots: [MapNode], overrides: [UUID: MapLayoutOverride] = [:]) -> [LaidOutNode] {
    #if HEADLESS_TEST
    mapLayoutInvocations += 1
    #endif
    if !overrides.isEmpty {
        // ponytail: two linear passes retain exact legacy deltas; combine passes if large imports become slow.
        let original = mapLayout(roots)
        let originalFrames = Dictionary(uniqueKeysWithValues: original.map { ($0.node.id, $0.frame) })
        var placed: [UUID: CGRect] = [:]
        return original.map { item in
            let node = item.node
            let saved = overrides[node.id]
            let size = mapNodeSize(node, font: saved?.font ?? mapFont(isRoot: item.parent == nil, node: node),
                                   isRoot: item.parent == nil, maxWidth: saved?.maxWidth,
                                   allowToShrinkWidth: saved?.allowToShrinkWidth ?? false)
            let width = size.width, height = size.height
            let parentShift: CGSize
            if let parent = item.parent, let actual = placed[parent], let baseline = originalFrames[parent] {
                parentShift = CGSize(width: actual.midX - baseline.midX, height: actual.midY - baseline.midY)
            } else { parentShift = .zero }
            let center = node.location.map { CGPoint(x: $0.x, y: $0.y) } ?? saved?.location
                ?? CGPoint(x: item.frame.midX + parentShift.width,
                                                      y: item.frame.midY + parentShift.height)
            let frame = CGRect(x: center.x - width / 2, y: center.y - height / 2,
                               width: width, height: height)
            placed[node.id] = frame
            return LaidOutNode(node: node, frame: frame, parent: item.parent)
        }
    }
    let gap: CGFloat = 24
    var sizes: [UUID: CGSize] = [:]
    var subtreeHeights: [UUID: CGFloat] = [:]
    var columnWidths: [CGFloat] = []

    @discardableResult
    func measure(_ node: MapNode, depth: Int) -> CGFloat {
        let size = mapNodeSize(node, font: mapFont(isRoot: depth == 0, node: node), isRoot: depth == 0)
        let width = size.width, height = size.height
        sizes[node.id] = size
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
        if depth == 0, children.count == 1, let child = children.first,
           let size = sizes[child.id], let height = subtreeHeights[child.id] {
            childTop = frame.midY - (height + size.height) / 2 + 7
        }
        for child in children {
            place(child, depth: depth + 1, parent: node.id, top: childTop)
            childTop += subtreeHeights[child.id]! + gap
        }
    }
    var top: CGFloat = 0
    for (root, height) in zip(roots, rootHeights) {
        if !root.folded, root.children.count == 1, let child = root.children.first {
            // The straight first branch lifts this subtree above its root's original top.
            top += max(0, (subtreeHeights[child.id]! + sizes[child.id]!.height - height) / 2 - 7)
        }
        place(root, depth: 0, parent: nil, top: top)
        top += height + gap
    }
    return result
}
