import Foundation

struct MapNode: Codable, Equatable {
    static let widthPresets: [CGFloat] = [170, 240, 320, 480]
    var id: UUID
    var title: String
    var children: [MapNode]
    var folded: Bool
    var width: CGFloat? = nil // nil keeps the original content-sized node for existing JSON maps.
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

    func moveNode(_ id: UUID, to parentID: UUID, at index: Int) -> Bool {
        guard canMoveNode(id, to: parentID, at: index) else { return false }
        let sourcePath = Self.path(to: id, in: roots)!
        let targetPath = Self.path(to: parentID, in: roots)!
        let sameParent = sourcePath.dropLast().elementsEqual(targetPath)
        let destinationIndex = index - (sameParent && sourcePath.last! < index ? 1 : 0)
        let moving = Self.node(at: sourcePath[...], in: roots)
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
    func setWidth(_ width: CGFloat?) -> Bool {
        guard width.map({ MapNode.widthPresets.contains($0) }) ?? true,
              let path = Self.path(to: selected, in: roots),
              Self.node(at: path[...], in: roots).width != width else { return false }
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in nodes[index].width = width }
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
