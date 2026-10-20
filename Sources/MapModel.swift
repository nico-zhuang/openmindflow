import Foundation

struct MapNode: Codable {
    var id: UUID
    var title: String
    var children: [MapNode]
    var folded: Bool
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
        guard let path = Self.path(to: selected, in: roots) else { return }
        let child = MapNode(id: UUID(), title: "", children: [], folded: false)
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes[index].folded = false
            nodes[index].children.append(child)
        }
        selected = child.id
    }

    func addSibling() {
        guard let path = Self.path(to: selected, in: roots), path.count > 1 else { return }
        let sibling = MapNode(id: UUID(), title: "", children: [], folded: false)
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes.insert(sibling, at: index + 1)
        }
        selected = sibling.id
    }

    func rename(_ title: String) {
        guard let path = Self.path(to: selected, in: roots),
              Self.node(at: path[...], in: roots).title != title else { return }
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes[index].title = title
        }
    }

    func remove() {
        guard let path = Self.path(to: selected, in: roots), path.count > 1 else { return }
        let parentID = Self.node(at: path.dropLast(), in: roots).id
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes.remove(at: index)
        }
        selected = parentID
    }

    func toggleFold() {
        guard let path = Self.path(to: selected, in: roots) else { return }
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes[index].folded.toggle()
        }
    }

    func undo() {
        guard let previous = past.popLast() else { return }
        future.append((roots, selected))
        (roots, selected) = previous
    }

    func redo() {
        guard let next = future.popLast() else { return }
        past.append((roots, selected))
        (roots, selected) = next
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
