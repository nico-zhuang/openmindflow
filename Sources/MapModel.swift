import Foundation

struct MapNode: Codable, Equatable {
    static let widthPresets: [CGFloat] = [170, 240, 320, 480]
    static func validWidth(_ width: CGFloat) -> Bool { width.isFinite && (60...1000).contains(width) }
    var id: UUID
    var title: String
    var children: [MapNode]
    var folded: Bool
    var width: CGFloat? = nil // nil keeps the original content-sized node for existing JSON maps.
    var location: SIMD2<Double>? = nil // Saved world center; stdlib vector stays Codable/Equatable without AppKit.
    var fontFamily: String? = nil
    var fontSize: Double? = nil
}

final class MapModel {
    var roots: [MapNode]
    var selected: UUID

    private typealias Snapshot = (roots: [MapNode], selected: UUID)
    private var past: [Snapshot] = []
    private var future: [Snapshot] = []

    init(roots: [MapNode], selected: UUID) {
        self.roots = roots
        self.selected = selected
    }

    func addChild() {
        if roots.isEmpty {
            save()
            let root = MapNode(id: UUID(), title: "", children: [], folded: false)
            roots = [root]
            selected = root.id
            return
        }
        guard let path = Self.path(to: selected, in: roots) else { return }
        let child = MapNode(id: UUID(), title: "", children: [], folded: false)
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes[index].folded = false
            nodes[index].children.append(child)
        }
        selected = child.id
    }

    func addSibling(before: Bool = false) {
        if roots.isEmpty { addChild(); return }
        guard let path = Self.path(to: selected, in: roots), path.count > 1 else { return }
        let sibling = MapNode(id: UUID(), title: "", children: [], folded: false)
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes.insert(sibling, at: index + (before ? 0 : 1))
        }
        selected = sibling.id
    }

    func addParent() {
        guard let path = Self.path(to: selected, in: roots), path.count > 1 else { return }
        let previous = Self.node(at: path[...], in: roots)
        let parent = MapNode(id: UUID(), title: "", children: [previous], folded: false)
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in nodes[index] = parent }
        selected = parent.id
    }

    func addMainNode() {
        let main = MapNode(id: UUID(), title: "", children: [], folded: false)
        let index = Self.path(to: selected, in: roots)?.first.map { $0 + 1 } ?? roots.count
        save()
        roots.insert(main, at: index)
        selected = main.id
    }

    @discardableResult
    func moveSibling(by step: Int) -> Bool {
        guard step == -1 || step == 1, let path = Self.path(to: selected, in: roots), path.count > 1,
              let index = path.last,
              Self.node(at: path.dropLast(), in: roots).children.indices.contains(index + step) else { return false }
        save()
        Self.edit(&roots, at: path.dropLast()) { nodes, parent in
            nodes[parent].children.swapAt(index, index + step)
        }
        return true
    }

    func canMoveNode(_ id: UUID, to parentID: UUID, at index: Int) -> Bool {
        guard let source = Self.path(to: id, in: roots), source.count > 1,
              let target = Self.path(to: parentID, in: roots),
              !target.starts(with: source),
              (0...Self.node(at: target[...], in: roots).children.count).contains(index) else { return false }
        let sameParent = source.dropLast().elementsEqual(target)
        let destination = index - (sameParent && source.last! < index ? 1 : 0)
        return !sameParent || destination != source.last!
    }

    func moveNode(_ id: UUID, to parentID: UUID, at index: Int, location: CGPoint? = nil) -> Bool {
        guard canMoveNode(id, to: parentID, at: index),
              location.map({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) ?? true
              else { return false }
        let sourcePath = Self.path(to: id, in: roots)!
        let targetPath = Self.path(to: parentID, in: roots)!
        let sameParent = sourcePath.dropLast().elementsEqual(targetPath)
        let destinationIndex = index - (sameParent && sourcePath.last! < index ? 1 : 0)
        var moving = Self.node(at: sourcePath[...], in: roots)
        if let location {
            if let old = moving.location {
                let dx = Double(location.x) - old.x, dy = Double(location.y) - old.y
                func shift(_ node: inout MapNode) -> Bool {
                    if let point = node.location {
                        let next = SIMD2<Double>(point.x + dx, point.y + dy)
                        guard next.x.isFinite, next.y.isFinite,
                              abs(next.x) <= 1_000_000, abs(next.y) <= 1_000_000 else { return false }
                        node.location = next
                    }
                    for index in node.children.indices where !shift(&node.children[index]) { return false }
                    return true
                }
                guard shift(&moving) else { return false }
            } else { moving.location = SIMD2(Double(location.x), Double(location.y)) }
        }
        save()
        Self.edit(&roots, at: sourcePath[...]) { nodes, position in nodes.remove(at: position) }
        let updatedParentPath = Self.path(to: parentID, in: roots)!
        Self.edit(&roots, at: updatedParentPath[...]) { nodes, position in
            nodes[position].folded = false
            nodes[position].children.insert(moving, at: destinationIndex)
        }
        return true
    }

    @discardableResult
    func detachSelected() -> Bool {
        guard let path = Self.path(to: selected, in: roots), path.count > 1 else { return false }
        let moving = Self.node(at: path[...], in: roots)
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in nodes.remove(at: index) }
        roots.insert(moving, at: path[0] + 1)
        return true
    }

    @discardableResult
    func setWidth(_ width: CGFloat?, anchoredFrom oldWidth: CGFloat? = nil) -> Bool {
        guard width.map(MapNode.validWidth) ?? true,
              oldWidth.map(MapNode.validWidth) ?? true,
              let path = Self.path(to: selected, in: roots) else { return false }
        let current = Self.node(at: path[...], in: roots)
        guard current.width != width else { return false }
        let centerX = current.location.flatMap { point -> Double? in
            guard let width, let oldWidth else { return nil }
            return point.x + Double(width - oldWidth) / 2
        }
        guard centerX.map({ $0.isFinite && abs($0) <= 1_000_000 }) ?? true else { return false }
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes[index].width = width
            if let centerX { nodes[index].location?.x = centerX }
        }
        return true
    }

    @discardableResult
    func setFont(family: String, size: Double) -> Bool {
        guard !family.isEmpty, family.utf8.count <= 128, size.isFinite, (6...240).contains(size),
              let path = Self.path(to: selected, in: roots) else { return false }
        let current = Self.node(at: path[...], in: roots)
        guard current.fontFamily != family || current.fontSize != size else { return false }
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes[index].fontFamily = family
            nodes[index].fontSize = size
        }
        return true
    }

    func rename(_ title: String) {
        guard let path = Self.path(to: selected, in: roots),
              Self.node(at: path[...], in: roots).title != title else { return }
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes[index].title = title
        }
    }

    @discardableResult
    func remove() -> Bool {
        guard let path = Self.path(to: selected, in: roots) else { return false }
        if path.count == 1 {
            guard roots.count > 1 else { return false }
            save()
            roots.remove(at: path[0])
            selected = roots[min(path[0], roots.count - 1)].id
            return true
        }
        let parentID = Self.node(at: path.dropLast(), in: roots).id
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes.remove(at: index)
        }
        selected = parentID
        return true
    }

    @discardableResult
    func toggleFold() -> Bool {
        guard let path = Self.path(to: selected, in: roots),
              !Self.node(at: path[...], in: roots).children.isEmpty else { return false }
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes[index].folded.toggle()
        }
        return true
    }

    @discardableResult
    func undo() -> Bool {
        guard let previous = past.popLast() else { return false }
        future.append((roots, selected))
        (roots, selected) = previous
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let next = future.popLast() else { return false }
        past.append((roots, selected))
        (roots, selected) = next
        return true
    }

    private func save() {
        past.append((roots, selected))
        future.removeAll()
    }

    private static func path(to id: UUID, in nodes: [MapNode]) -> [Int]? {
        for (index, node) in nodes.enumerated() {
            if node.id == id { return [index] }
            if let childPath = path(to: id, in: node.children) { return [index] + childPath }
        }
        return nil
    }

    private static func node(at path: ArraySlice<Int>, in nodes: [MapNode]) -> MapNode {
        let node = nodes[path.first!]
        return path.count == 1 ? node : self.node(at: path.dropFirst(), in: node.children)
    }

    private static func edit(_ nodes: inout [MapNode], at path: ArraySlice<Int>,
                             _ change: (inout [MapNode], Int) -> Void) {
        let index = path.first!
        if path.count == 1 {
            change(&nodes, index)
        } else {
            edit(&nodes[index].children, at: path.dropFirst(), change)
        }
    }
}
