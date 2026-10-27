import Foundation
import ImageIO

enum MapImageError: LocalizedError {
    case tooLarge, invalidFormat, invalidData, invalidDimensions

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "An image must be 8 MiB or smaller."
        case .invalidFormat: return "Use a PNG, JPEG, or HEIC image."
        case .invalidData: return "The image is damaged or incomplete."
        case .invalidDimensions: return "An image must be at most 4096 pixels per side and 16 million pixels total."
        }
    }
}

struct MapImage: Codable, Equatable {
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int

    init(data: Data) throws {
        guard data.count <= 8 * 1024 * 1024 else { throw MapImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              ["public.png", "public.jpeg", "public.heic", "public.heif"].contains(type) else {
            throw MapImageError.invalidFormat
        }
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw MapImageError.invalidData }
        guard (1...4096).contains(width), (1...4096).contains(height), width * height <= 16_000_000 else {
            throw MapImageError.invalidDimensions
        }
        guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else {
            throw MapImageError.invalidData
        }
        self.data = data
        pixelWidth = width
        pixelHeight = height
    }

    func displaySize(width: CGFloat? = nil) -> CGSize {
        let ratio = CGFloat(pixelWidth) / CGFloat(pixelHeight)
        let fitted = min(296, CGFloat(pixelWidth), 296 * ratio)
        let actualWidth = min(width ?? fitted, 1000 * ratio)
        return CGSize(width: actualWidth, height: actualWidth / ratio)
    }

    private enum CodingKeys: String, CodingKey { case data }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(data: container.decode(Data.self, forKey: .data))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
    }
}

struct MapNode: Codable, Equatable {
    static let widthPresets: [CGFloat] = [170, 240, 320, 480]
    static func validWidth(_ width: CGFloat) -> Bool { width.isFinite && (60...1000).contains(width) }
    static func validColor(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 9 && bytes[0] == 35 && bytes.dropFirst().allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }
    var id: UUID
    var title: String
    var children: [MapNode]
    var folded: Bool
    var width: CGFloat? = nil // nil keeps the original content-sized node for existing JSON maps.
    var location: SIMD2<Double>? = nil // Saved world center; stdlib vector stays Codable/Equatable without AppKit.
    var fontFamily: String? = nil
    var fontSize: Double? = nil
    var textAlignment: String? = nil
    var branchStrokeWidth: CGFloat? = nil
    var branchStrokeColor: String? = nil
    var strokeStyle: String? = nil
    var image: MapImage? = nil
    var imageWidth: CGFloat? = nil // nil fits the picture within a 296pt square.
    var video: MapVideo? = nil
    var videoWidth: CGFloat? = nil // nil fits the clip within a 296pt square.
    var note: String? = nil
    var rootShape: String? = nil
    var rootFillColor: String? = nil
    var branchSide: String? = nil // Only first-level children may explicitly choose left or right.
}

struct MapSelectionClip: Codable {
    let roots: [MapNode]
    let relationships: [MapRelationship]
}

final class MapModel {
    static let maxSavedJSONBytes = 32 * 1024 * 1024
    private static func fitsSavedJSON(_ roots: [MapNode], relationships: [MapRelationship],
                                      theme: String?, canvasColor: String?) -> Bool {
        let encoder = JSONEncoder()
        let size = relationships.isEmpty && theme == nil && canvasColor == nil
            ? try? encoder.encode(roots).count
            : try? encoder.encode(OwnMapDocument(roots: roots, relationships: relationships,
                                                 theme: theme, canvasColor: canvasColor)).count
        return size.map { $0 <= maxSavedJSONBytes } ?? false
    }
    private func fitsSavedJSON(_ roots: [MapNode], relationships: [MapRelationship]) -> Bool {
        Self.fitsSavedJSON(roots, relationships: relationships, theme: theme, canvasColor: canvasColor)
    }
    var roots: [MapNode]
    var relationships: [MapRelationship] = []
    private(set) var theme: String?
    private(set) var canvasColor: String?
    var selected: UUID { didSet { selectedIDs = [selected]; selectionAnchor = selected } }
    private(set) var selectedIDs: Set<UUID>
    private var selectionAnchor: UUID
    private var pendingInitialWidth: Set<UUID> = []

    private typealias Snapshot = (roots: [MapNode], relationships: [MapRelationship], theme: String?, canvasColor: String?, selected: UUID, selectedIDs: Set<UUID>, anchor: UUID, pending: Set<UUID>)
    private var past: [Snapshot] = []
    private var future: [Snapshot] = []

    init(roots: [MapNode], selected: UUID, theme: String? = nil, canvasColor: String? = nil) {
        self.roots = roots
        self.theme = theme
        self.canvasColor = canvasColor
        self.selected = selected
        selectedIDs = [selected]
        selectionAnchor = selected
    }

    func copySelection(visibleCenters: [UUID: CGPoint] = [:]) -> MapSelectionClip? {
        let selected = selectedPaths()
        let outer = selected.filter { path in
            !selected.contains { $0.count < path.count && path.starts(with: $0) }
        }
        guard !outer.isEmpty else { return nil }
        var group = outer.map { Self.node(at: $0[...], in: roots) }
        for index in group.indices where group[index].location == nil {
            guard let point = visibleCenters[group[index].id], point.x.isFinite, point.y.isFinite,
                  abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000 else { return nil }
            group[index].location = SIMD2(Double(point.x), Double(point.y))
        }
        var copiedIDs = Set<UUID>()
        func collect(_ node: MapNode) {
            copiedIDs.insert(node.id)
            node.children.forEach(collect)
        }
        group.forEach(collect)
        let clip = MapSelectionClip(roots: group, relationships: relationships.filter {
            copiedIDs.contains($0.from) && copiedIDs.contains($0.to)
        })
        guard (try? JSONEncoder().encode(clip).count).map({ $0 <= Self.maxSavedJSONBytes }) ?? false else { return nil }
        return clip
    }

    @discardableResult
    func pasteSelection(_ clip: MapSelectionClip, at anchor: CGPoint, into parentID: UUID? = nil) -> Bool {
        guard anchor.x.isFinite, anchor.y.isFinite,
              abs(anchor.x) <= 1_000_000, abs(anchor.y) <= 1_000_000,
              !clip.roots.isEmpty, (parentID != nil || clip.roots.first?.location != nil),
              (try? JSONEncoder().encode(clip).count).map({ $0 <= Self.maxSavedJSONBytes }) ?? false else { return false }
        let parentPath = parentID.flatMap { Self.path(to: $0, in: roots) }
        guard parentID == nil || parentPath != nil else { return false }
        var normalizedRoots = clip.roots
        func normalize(_ node: inout MapNode, isChildPaste: Bool, keepFirstLevelSide: Bool = false) {
            if !keepFirstLevelSide { node.branchSide = nil }
            if isChildPaste { node.rootShape = nil; node.rootFillColor = nil }
            if isChildPaste {
                for index in node.children.indices { normalize(&node.children[index], isChildPaste: true) }
            }
        }
        for index in normalizedRoots.indices {
            normalize(&normalizedRoots[index], isChildPaste: parentID != nil,
                      keepFirstLevelSide: parentPath?.count == 1)
        }
        // The clipboard envelope treats selected branches as roots. Validate that
        // envelope with root-only side cleared, then validate the actual attached
        // document below so a preserved first-level left side is legal there.
        var validationRoots = normalizedRoots
        for index in validationRoots.indices { validationRoots[index].branchSide = nil }
        guard let oldIDs = try? checkOwnJSONNodes(validationRoots),
              sanitizeRelationships(clip.relationships, nodeIDs: oldIDs).count == clip.relationships.count else { return false }
        let first = clip.roots.first?.location
        let delta = parentID == nil ? SIMD2(Double(anchor.x) - first!.x, Double(anchor.y) - first!.y)
                                    : SIMD2<Double>(0, 0)
        var idMap: [UUID: UUID] = [:]
        func clone(_ node: MapNode) -> MapNode? {
            var result = node
            result.id = UUID()
            idMap[node.id] = result.id
            if parentID != nil {
                result.location = nil // Let the destination branch layout place the whole copied subtree.
            } else if let old = result.location {
                let next = old + delta
                guard next.x.isFinite, next.y.isFinite,
                      abs(next.x) <= 1_000_000, abs(next.y) <= 1_000_000 else { return nil }
                result.location = next
            }
            var children: [MapNode] = []
            for child in node.children {
                guard let next = clone(child) else { return nil }
                children.append(next)
            }
            result.children = children
            return result
        }
        var copies: [MapNode] = []
        for root in normalizedRoots {
            guard let next = clone(root) else { return false }
            copies.append(next)
        }
        let edges = remapRelationships(clip.relationships, nodeIDs: idMap)
        guard edges.count == clip.relationships.count else { return false }
        var updated = roots
        if let parentPath {
            Self.edit(&updated, at: parentPath[...]) { nodes, index in
                nodes[index].folded = false
                nodes[index].children.append(contentsOf: copies)
            }
        } else { updated.append(contentsOf: copies) }
        guard fitsSavedJSON(updated, relationships: relationships + edges) else { return false }
        save()
        roots = updated
        relationships.append(contentsOf: edges)
        selected = copies[0].id
        selectedIDs = Set(copies.map(\.id))
        return true
    }

    private func allNodeIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        func visit(_ node: MapNode) {
            ids.insert(node.id)
            node.children.forEach(visit)
        }
        roots.forEach(visit)
        return ids
    }

    @discardableResult
    func setRelationship(_ edge: MapRelationship) -> Bool {
        guard validRelationship(edge, nodeIDs: allNodeIDs()) else { return false }
        var updated = relationships
        if let index = updated.firstIndex(where: { $0.id == edge.id }) {
            guard updated[index] != edge else { return false }
            updated[index] = edge
        } else { updated.append(edge) }
        guard fitsSavedJSON(roots, relationships: updated) else { return false }
        save()
        relationships = updated
        return true
    }

    @discardableResult
    func removeRelationship(_ id: UUID) -> Bool {
        guard let index = relationships.firstIndex(where: { $0.id == id }) else { return false }
        save()
        relationships.remove(at: index)
        return true
    }

    @discardableResult
    func clearSelection() -> Bool { selectNodes([]) }

    @discardableResult
    func selectOnly(_ id: UUID) -> Bool {
        guard Self.path(to: id, in: roots) != nil else { return false }
        let changed = selectedIDs != [id]
        selected = id
        return changed
    }

    @discardableResult
    func selectNodes(_ ids: Set<UUID>) -> Bool {
        let paths = ids.compactMap { id in Self.path(to: id, in: roots).map { (id, $0) } }
        guard paths.count == ids.count else { return false }
        let primary = ids.contains(selected) ? selected : paths.min {
            $0.1.lexicographicallyPrecedes($1.1)
        }?.0
        guard selectedIDs != ids || (primary != nil && selected != primary) else { return false }
        if let primary, selected != primary { selected = primary }
        selectedIDs = ids
        return true
    }

    @discardableResult
    func revealSearchResult(_ id: UUID) -> Bool {
        guard let path = Self.path(to: id, in: roots) else { return false }
        var updated = roots
        for depth in 1..<path.count {
            Self.edit(&updated, at: path.prefix(depth)) { nodes, index in nodes[index].folded = false }
        }
        let expanded = updated != roots
        if expanded && !commit(updated) { return false }
        selected = id
        return expanded
    }

    @discardableResult
    func toggleSelection(_ id: UUID) -> Bool {
        guard Self.path(to: id, in: roots) != nil else { return false }
        if selectedIDs.contains(id) {
            guard selectedIDs.count > 1 else { return false }
            let remaining = selectedIDs.subtracting([id])
            guard let next = selectedPaths().map({ Self.node(at: $0[...], in: roots).id })
                .first(where: { remaining.contains($0) }) else { return false }
            selected = next
            selectedIDs = remaining
        } else {
            let union = selectedIDs.union([id])
            selected = id
            selectedIDs = union
        }
        return true
    }

    @discardableResult
    func selectRange(to id: UUID) -> Bool {
        guard !selectedIDs.isEmpty,
              let from = Self.path(to: selectionAnchor, in: roots), let to = Self.path(to: id, in: roots),
              from.dropLast().elementsEqual(to.dropLast()), let start = from.last, let end = to.last else { return false }
        let siblings = from.count == 1 ? roots : Self.node(at: from.dropLast(), in: roots).children
        let range = Set(siblings[min(start, end)...max(start, end)].map(\.id))
        let changed = selectedIDs != range || selected != id
        let anchor = selectionAnchor
        selected = id
        selectedIDs = range
        selectionAnchor = anchor
        return changed
    }

    @discardableResult
    func setRootBranchSide(_ side: String, for id: UUID) -> Bool {
        guard side == "left" || side == "right",
              let path = Self.path(to: id, in: roots), path.count == 2,
              Self.node(at: path[...], in: roots).branchSide != side else { return false }
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in
            nodes[index].branchSide = side
            Self.clearLocations(&nodes[index])
        }
        return commit(updated)
    }

    private static func clearLocations(_ node: inout MapNode) {
        node.location = nil
        for index in node.children.indices { clearLocations(&node.children[index]) }
    }

    func addChild() {
        if roots.isEmpty {
            let root = MapNode(id: UUID(), title: "", children: [], folded: false)
            guard commit([root]) else { return }
            selected = root.id
            pendingInitialWidth.insert(root.id)
            return
        }
        guard selectedIDs.contains(selected), let path = Self.path(to: selected, in: roots) else { return }
        let child = MapNode(id: UUID(), title: "", children: [], folded: false)
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in
            nodes[index].folded = false
            nodes[index].children.append(child)
        }
        guard commit(updated) else { return }
        selected = child.id
        pendingInitialWidth.insert(child.id)
    }

    @discardableResult
    func addImageChild(_ image: MapImage) -> Bool {
        guard selectedIDs.contains(selected) else { return false }
        return addImageChild(image, to: selected)
    }
    @discardableResult
    func addImageChild(_ image: MapImage, to parentID: UUID) -> Bool {
        guard let path = Self.path(to: parentID, in: roots) else { return false }
        let parent = Self.node(at: path[...], in: roots)
        let child = MapNode(id: UUID(), title: "", children: [], folded: false,
                            fontFamily: parent.fontFamily, fontSize: parent.fontSize,
                            textAlignment: parent.textAlignment, image: image)
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in
            nodes[index].folded = false
            nodes[index].children.append(child)
        }
        guard fitsSavedJSON(updated, relationships: relationships) else { return false }
        save()
        roots = updated
        selected = child.id
        return true
    }

    @discardableResult
    func addVideoChild(_ video: MapVideo) -> Bool {
        guard selectedIDs.contains(selected) else { return false }
        return addVideoChild(video, to: selected)
    }
    @discardableResult
    func addVideoChild(_ video: MapVideo, to parentID: UUID) -> Bool {
        guard let path = Self.path(to: parentID, in: roots) else { return false }
        let parent = Self.node(at: path[...], in: roots)
        let child = MapNode(id: UUID(), title: "", children: [], folded: false,
                            fontFamily: parent.fontFamily, fontSize: parent.fontSize,
                            textAlignment: parent.textAlignment, video: video)
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in
            nodes[index].folded = false
            nodes[index].children.append(child)
        }
        guard fitsSavedJSON(updated, relationships: relationships) else { return false }
        save()
        roots = updated
        selected = child.id
        return true
    }

    func addSibling(before: Bool = false) {
        if roots.isEmpty { addChild(); return }
        guard selectedIDs.contains(selected),
              let path = Self.path(to: selected, in: roots), path.count > 1 else { return }
        let inheritedSide = path.count == 2 ? Self.node(at: path[...], in: roots).branchSide : nil
        let sibling = MapNode(id: UUID(), title: "", children: [], folded: false,
                              branchSide: inheritedSide)
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in
            nodes.insert(sibling, at: index + (before ? 0 : 1))
        }
        guard commit(updated) else { return }
        selected = sibling.id
        pendingInitialWidth.insert(sibling.id)
    }

    func addParent() {
        guard selectedIDs.contains(selected),
              let path = Self.path(to: selected, in: roots), path.count > 1 else { return }
        var previous = Self.node(at: path[...], in: roots)
        let inheritedSide = path.count == 2 ? previous.branchSide : nil
        if path.count == 2 { previous.branchSide = nil }
        let parent = MapNode(id: UUID(), title: "", children: [previous], folded: false,
                             branchSide: inheritedSide)
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in nodes[index] = parent }
        guard commit(updated) else { return }
        selected = parent.id
        pendingInitialWidth.insert(parent.id)
    }

    @discardableResult
    func insertRoot(title: String, image: MapImage? = nil, video: MapVideo? = nil,
                    at worldCenter: CGPoint) -> Bool {
        guard worldCenter.x.isFinite, worldCenter.y.isFinite,
              abs(worldCenter.x) <= 1_000_000, abs(worldCenter.y) <= 1_000_000,
              title.utf8.count <= 65_536, image == nil || video == nil else { return false }
        let root = MapNode(id: UUID(), title: title, children: [], folded: false,
                           location: SIMD2(Double(worldCenter.x), Double(worldCenter.y)),
                           image: image, video: video)
        let updated = roots + [root]
        guard fitsSavedJSON(updated, relationships: relationships) else { return false }
        save()
        roots = updated
        selected = root.id
        if title.isEmpty { pendingInitialWidth.insert(root.id) }
        return true
    }

    func addMainNode() {
        let main = MapNode(id: UUID(), title: "", children: [], folded: false)
        let index = selectedIDs.contains(selected) ?
            (Self.path(to: selected, in: roots)?.first.map { $0 + 1 } ?? roots.count) : roots.count
        var updated = roots
        updated.insert(main, at: index)
        guard commit(updated) else { return }
        selected = main.id
        pendingInitialWidth.insert(main.id)
    }

    @discardableResult
    func moveSibling(by step: Int) -> Bool {
        guard selectedIDs.contains(selected), step == -1 || step == 1,
              let path = Self.path(to: selected, in: roots), path.count > 1,
              let index = path.last,
              Self.node(at: path.dropLast(), in: roots).children.indices.contains(index + step) else { return false }
        save()
        Self.edit(&roots, at: path.dropLast()) { nodes, parent in
            nodes[parent].children.swapAt(index, index + step)
        }
        return true
    }

    func canMoveNode(_ id: UUID, to parentID: UUID, at index: Int) -> Bool {
        guard let source = Self.path(to: id, in: roots),
              let target = Self.path(to: parentID, in: roots),
              !target.starts(with: source),
              (0...Self.node(at: target[...], in: roots).children.count).contains(index) else { return false }
        let sameParent = source.dropLast().elementsEqual(target)
        let destination = index - (sameParent && source.last! < index ? 1 : 0)
        return !sameParent || destination != source.last!
    }

    func moveNode(_ id: UUID, to parentID: UUID, at index: Int, location: CGPoint? = nil,
                  branchSide: String? = nil) -> Bool {
        guard canMoveNode(id, to: parentID, at: index),
              (branchSide == nil || branchSide == "left" || branchSide == "right"),
              location.map({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) ?? true
              else { return false }
        let sourcePath = Self.path(to: id, in: roots)!
        let targetPath = Self.path(to: parentID, in: roots)!
        let sameParent = sourcePath.dropLast().elementsEqual(targetPath)
        let destinationIndex = index - (sameParent && sourcePath.last! < index ? 1 : 0)
        var moving = Self.node(at: sourcePath[...], in: roots)
        if sourcePath.count == 1 {
            // A free-position root becomes a laid-out branch. Neither its root
            // appearance nor its former absolute subtree coordinates fit there.
            moving.rootShape = nil
            moving.rootFillColor = nil
            func resetBranch(_ node: inout MapNode) {
                node.location = nil
                node.branchSide = nil
                for index in node.children.indices { resetBranch(&node.children[index]) }
            }
            resetBranch(&moving)
            if targetPath.count == 1 { moving.branchSide = branchSide }
        } else if targetPath.count != 1 { moving.branchSide = nil }
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
        var updated = roots
        Self.edit(&updated, at: sourcePath[...]) { nodes, position in nodes.remove(at: position) }
        let updatedParentPath = Self.path(to: parentID, in: updated)!
        Self.edit(&updated, at: updatedParentPath[...]) { nodes, position in
            nodes[position].folded = false
            nodes[position].children.insert(moving, at: destinationIndex)
        }
        return commit(updated)
    }

    @discardableResult
    func moveSelectedNodes(to parentID: UUID, at index: Int, locations: [UUID: CGPoint]? = nil) -> Bool {
        let selected = selectedPaths()
        // ponytail: small selections scan ancestor paths; index them if large group drags become slow.
        let paths = selected.filter { path in
            !selected.contains { $0.count < path.count && path.starts(with: $0) }
        }
        guard !paths.isEmpty, paths.allSatisfy({ $0.count > 1 }),
              let targetPath = Self.path(to: parentID, in: roots),
              !paths.contains(where: { targetPath.starts(with: $0) }),
              (0...Self.node(at: targetPath[...], in: roots).children.count).contains(index),
              locations.map({ Set($0.keys) == Set(paths.map { Self.node(at: $0[...], in: roots).id }) }) ?? true
        else { return false }
        var moving = paths.map { Self.node(at: $0[...], in: roots) }
        if targetPath.count != 1 {
            for position in moving.indices { moving[position].branchSide = nil }
        }
        if let locations {
            for position in moving.indices {
                let point = locations[moving[position].id]!
                guard point.x.isFinite, point.y.isFinite,
                      abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000 else { return false }
                if let old = moving[position].location {
                    let dx = Double(point.x) - old.x, dy = Double(point.y) - old.y
                    func shift(_ node: inout MapNode) -> Bool {
                        if let old = node.location {
                            let next = SIMD2(old.x + dx, old.y + dy)
                            guard next.x.isFinite, next.y.isFinite,
                                  abs(next.x) <= 1_000_000, abs(next.y) <= 1_000_000 else { return false }
                            node.location = next
                        }
                        for child in node.children.indices where !shift(&node.children[child]) { return false }
                        return true
                    }
                    guard shift(&moving[position]) else { return false }
                } else { moving[position].location = SIMD2(Double(point.x), Double(point.y)) }
            }
        }
        var updated = roots
        for path in paths.reversed() {
            Self.edit(&updated, at: path[...]) { nodes, at in nodes.remove(at: at) }
        }
        let preceding = paths.filter { $0.dropLast().elementsEqual(targetPath) && $0.last! < index }.count
        guard let destination = Self.path(to: parentID, in: updated) else { return false }
        Self.edit(&updated, at: destination[...]) { nodes, at in
            nodes[at].children.insert(contentsOf: moving, at: index - preceding)
        }
        guard updated != roots else { return false }
        Self.edit(&updated, at: destination[...]) { nodes, at in nodes[at].folded = false }
        return commit(updated)
    }

    @discardableResult
    func translateSelectedSubtrees(by delta: CGPoint, visibleCenters: [UUID: CGPoint]) -> Bool {
        guard delta.x.isFinite, delta.y.isFinite, delta != .zero else { return false }
        let selected = selectedPaths()
        let paths = selected.filter { path in
            !selected.contains { $0.count < path.count && path.starts(with: $0) }
        }
        guard !paths.isEmpty else { return false }
        var updated = roots
        func move(_ node: inout MapNode, isRoot: Bool) -> Bool {
            if let point = node.location {
                let x = point.x + Double(delta.x), y = point.y + Double(delta.y)
                guard x.isFinite, y.isFinite, abs(x) <= 1_000_000, abs(y) <= 1_000_000 else { return false }
                node.location = SIMD2(x, y)
            } else if isRoot {
                guard let point = visibleCenters[node.id], point.x.isFinite, point.y.isFinite else { return false }
                let x = Double(point.x + delta.x), y = Double(point.y + delta.y)
                guard x.isFinite, y.isFinite, abs(x) <= 1_000_000, abs(y) <= 1_000_000 else { return false }
                node.location = SIMD2(x, y)
            }
            for index in node.children.indices where !move(&node.children[index], isRoot: false) { return false }
            return true
        }
        for path in paths {
            var valid = true
            Self.edit(&updated, at: path[...]) { nodes, index in
                valid = move(&nodes[index], isRoot: true)
            }
            guard valid else { return false }
        }
        guard updated != roots else { return false }
        return commit(updated)
    }

    @discardableResult
    func arrange(at centers: [UUID: CGPoint]) -> Bool {
        var updated = roots
        var seen = Set<UUID>()
        func place(_ nodes: inout [MapNode]) -> Bool {
            for index in nodes.indices {
                let id = nodes[index].id
                guard seen.insert(id).inserted, let point = centers[id],
                      point.x.isFinite, point.y.isFinite,
                      abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000 else { return false }
                nodes[index].location = SIMD2(Double(point.x), Double(point.y))
                if !place(&nodes[index].children) { return false }
            }
            return true
        }
        guard place(&updated), seen.count == centers.count, updated != roots else { return false }
        return commit(updated)
    }

    @discardableResult
    func detachSelected() -> Bool {
        guard selectedIDs.contains(selected),
              let path = Self.path(to: selected, in: roots), path.count > 1 else { return false }
        var moving = Self.node(at: path[...], in: roots)
        moving.branchSide = nil
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in nodes.remove(at: index) }
        updated.insert(moving, at: path[0] + 1)
        return commit(updated)
    }

    private func widthDirection(at path: [Int], renderedLeft: Set<UUID> = []) -> Double {
        guard path.count > 1 else { return 1 }
        let branch = roots[path[0]].children[path[1]]
        if branch.branchSide == "left" { return -1 }
        if branch.branchSide == "right" { return 1 }
        if renderedLeft.contains(branch.id) { return -1 }
        if let branchX = branch.location?.x, let rootX = roots[path[0]].location?.x,
           branchX < rootX { return -1 }
        return 1
    }

    private static func shiftPositioned(_ children: inout [MapNode], by distance: Double) {
        for index in children.indices {
            children[index].location?.x += distance
            shiftPositioned(&children[index].children, by: distance)
        }
    }

    @discardableResult
    func setWidth(_ width: CGFloat?, anchoredFrom oldWidth: CGFloat? = nil) -> Bool {
        guard width.map(MapNode.validWidth) ?? true, oldWidth.map(MapNode.validWidth) ?? true,
              selectedPaths().allSatisfy({ path in
                  let node = Self.node(at: path[...], in: roots)
                  guard node.width != width, let width, let oldWidth, let point = node.location else { return true }
                  let center = point.x + Double(width - oldWidth) * widthDirection(at: path) / 2
                  return center.isFinite && abs(center) <= 1_000_000
              }) else { return false }
        let directions = Dictionary(uniqueKeysWithValues: selectedPaths().map { path in
            (Self.node(at: path[...], in: roots).id, widthDirection(at: path))
        })
        if let width, let oldWidth {
            let shifts = Dictionary(uniqueKeysWithValues: selectedPaths().map { path -> (UUID, Double) in
                let node = Self.node(at: path[...], in: roots)
                return (node.id, node.width == width ? 0 : Double(width - oldWidth) * directions[node.id]!)
            })
            func safe(_ node: MapNode, ancestor: Double) -> Bool {
                let own = shifts[node.id] ?? 0
                if let point = node.location,
                   (!point.x.isFinite || abs(point.x + ancestor + own / 2) > 1_000_000) { return false }
                return node.children.allSatisfy { safe($0, ancestor: ancestor + own) }
            }
            guard roots.allSatisfy({ safe($0, ancestor: 0) }) else { return false }
        }
        return editSelected { node in
            guard node.width != width else { return }
            if let width, let oldWidth {
                let distance = Double(width - oldWidth) * directions[node.id]!
                node.location?.x += distance / 2
                Self.shiftPositioned(&node.children, by: distance)
            }
            node.width = width
        }
    }

    @discardableResult
    func resizeSelected(by delta: CGFloat, visibleWidths: [UUID: CGFloat],
                        visibleCenters: [UUID: CGPoint] = [:], renderedLeft: Set<UUID> = []) -> Bool {
        guard delta.isFinite, !visibleWidths.isEmpty,
              visibleCenters.values.allSatisfy({ $0.x.isFinite && $0.y.isFinite &&
                  abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) else { return false }
        let paths = selectedPaths()
        guard !paths.isEmpty, paths.allSatisfy({ path in
            let node = Self.node(at: path[...], in: roots)
            guard let old = visibleWidths[node.id], MapNode.validWidth(old) else { return false }
            let width = min(1000, max(60, old + delta))
            guard width.isFinite else { return false }
            guard node.width != width, let point = node.location else { return true }
            let center = point.x + Double(width - old) * widthDirection(at: path, renderedLeft: renderedLeft) / 2
            return center.isFinite && abs(center) <= 1_000_000
        }) else { return false }
        let shifts = Dictionary(uniqueKeysWithValues: paths.map { path in
            let node = Self.node(at: path[...], in: roots)
            let old = visibleWidths[node.id]!
            let width = min(1000, max(60, old + delta))
            return (node.id, node.width == width ? 0 : Double(width - old) * widthDirection(at: path, renderedLeft: renderedLeft))
        })
        func safe(_ node: MapNode, ancestor: Double) -> Bool {
            let own = shifts[node.id] ?? 0
            let displacement = ancestor + own / 2
            if let point = node.location {
                guard point.x.isFinite && point.y.isFinite,
                      abs(point.x + displacement) <= 1_000_000 else { return false }
            } else if displacement != 0, let center = visibleCenters[node.id] {
                guard abs(center.x + displacement) <= 1_000_000 else { return false }
            }
            return node.children.allSatisfy { safe($0, ancestor: ancestor + own) }
        }
        guard roots.allSatisfy({ safe($0, ancestor: 0) }) else { return false }
        func shiftChildren(_ children: inout [MapNode], by distance: Double) {
            guard distance != 0 else { return }
            for index in children.indices {
                if children[index].location == nil, let center = visibleCenters[children[index].id] {
                    children[index].location = SIMD2(Double(center.x) + distance, Double(center.y))
                } else { children[index].location?.x += distance }
                shiftChildren(&children[index].children, by: distance)
            }
        }
        return editSelected { node in
            let old = visibleWidths[node.id]!
            let width = min(1000, max(60, old + delta))
            guard node.width != width else { return }
            let distance = shifts[node.id]!
            if node.location == nil, let center = visibleCenters[node.id] {
                node.location = SIMD2(Double(center.x) + distance / 2, Double(center.y))
            } else { node.location?.x += distance / 2 }
            shiftChildren(&node.children, by: distance)
            node.width = width
        }
    }

    @discardableResult
    func setImage(_ image: MapImage?, displayWidth: CGFloat? = nil) -> Bool {
        guard displayWidth.map({ image != nil && $0.isFinite && (60...1000).contains($0) }) ?? true else { return false }
        if image != nil {
            var updated = roots
            for path in selectedPaths() {
                Self.edit(&updated, at: path[...]) { nodes, index in
                    nodes[index].image = image
                    nodes[index].imageWidth = displayWidth
                    nodes[index].video = nil
                    nodes[index].videoWidth = nil
                }
            }
            guard fitsSavedJSON(updated, relationships: relationships) else { return false }
        }
        return editSelected { node in
            node.image = image
            node.imageWidth = image == nil ? nil : displayWidth
            if image != nil { node.video = nil; node.videoWidth = nil }
        }
    }

    @discardableResult
    func setImageWidth(_ width: CGFloat) -> Bool {
        guard width.isFinite, (60...1000).contains(width),
              selectedPaths().allSatisfy({ Self.node(at: $0[...], in: roots).image != nil }) else { return false }
        return editSelected { $0.imageWidth = width }
    }

    @discardableResult
    func setVideoWidth(_ width: CGFloat) -> Bool {
        guard width.isFinite, (60...1000).contains(width),
              selectedPaths().allSatisfy({ Self.node(at: $0[...], in: roots).video != nil }) else { return false }
        return editSelected { $0.videoWidth = width }
    }

    @discardableResult
    func setFont(family: String? = nil, size: Double? = nil) -> Bool {
        guard family != nil || size != nil,
              family.map({ !$0.isEmpty && $0.utf8.count <= 128 }) ?? true,
              size.map({ $0.isFinite && (6...240).contains($0) }) ?? true else { return false }
        return editSelected { node in
            if let family { node.fontFamily = family }
            if let size { node.fontSize = size }
        }
    }

    @discardableResult
    func setAlignment(_ value: String?) -> Bool {
        guard value.map({ ["left", "center", "right", "justify"].contains($0) }) ?? true else { return false }
        return editSelected { $0.textAlignment = value }
    }

    @discardableResult
    func setBranchStroke(width: CGFloat? = nil, color: String? = nil, style: String? = nil) -> Bool {
        guard width != nil || color != nil || style != nil,
              width.map({ $0.isFinite && (0.5...16).contains($0) }) ?? true,
              color.map({ value in
                  let bytes = Array(value.utf8)
                  return bytes.count == 9 && bytes[0] == 35 && bytes.dropFirst().allSatisfy {
                      (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                  }
              }) ?? true,
              style.map({ $0 == "solid" || $0 == "dashed" }) ?? true else { return false }
        return editSelected { node in
            if let width { node.branchStrokeWidth = width }
            if let color { node.branchStrokeColor = color.uppercased() }
            if let style { node.strokeStyle = style }
        }
    }

    @discardableResult
    func setNote(_ text: String) -> Bool {
        guard text.utf8.count <= 65_536, selectedPaths().count == 1 else { return false }
        return editSelected { $0.note = text.isEmpty ? nil : text }
    }

    @discardableResult
    func setNote(_ text: String, for id: UUID) -> Bool {
        guard text.utf8.count <= 65_536, let path = Self.path(to: id, in: roots) else { return false }
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in
            nodes[index].note = text.isEmpty ? nil : text
        }
        guard updated != roots, fitsSavedJSON(updated, relationships: relationships) else { return false }
        save()
        roots = updated
        return true
    }

    @discardableResult
    func setRootShape(_ value: String?) -> Bool {
        guard value.map({ ["rectangle", "rounded"].contains($0) }) ?? true,
              selectedPaths().allSatisfy({ $0.count == 1 }) else { return false }
        return editSelected { $0.rootShape = value }
    }

    @discardableResult
    func setRootFillColor(_ value: String?) -> Bool {
        guard value.map(MapNode.validColor) ?? true,
              selectedPaths().allSatisfy({ $0.count == 1 }) else { return false }
        return editSelected { $0.rootFillColor = value?.uppercased() }
    }

    @discardableResult
    func setTheme(_ value: String?) -> Bool {
        guard value.map({ InspectorTheme(rawValue: $0) != nil }) ?? true,
              value != theme,
              Self.fitsSavedJSON(roots, relationships: relationships, theme: value, canvasColor: canvasColor)
        else { return false }
        save()
        theme = value
        return true
    }

    @discardableResult
    func setCanvasColor(_ value: String?) -> Bool {
        guard value.map(MapNode.validColor) ?? true else { return false }
        let color = value?.uppercased()
        guard color != canvasColor,
              Self.fitsSavedJSON(roots, relationships: relationships, theme: theme, canvasColor: color)
        else { return false }
        save()
        canvasColor = color
        return true
    }

    @discardableResult
    func resetStrokeStyle() -> Bool { editSelected { $0.strokeStyle = nil } }
    @discardableResult
    func resetStrokeColor() -> Bool { editSelected { $0.branchStrokeColor = nil } }
    @discardableResult
    func resetStrokeWidth() -> Bool { editSelected { $0.branchStrokeWidth = nil } }

    @discardableResult
    func rename(_ title: String, initialWidth: CGFloat? = nil) -> Bool {
        guard selectedIDs.contains(selected), let path = Self.path(to: selected, in: roots) else { return false }
        guard Self.node(at: path[...], in: roots).title != title else { return true }
        let firstWidth = pendingInitialWidth.contains(selected) && !title.isEmpty &&
            Self.node(at: path[...], in: roots).width == nil &&
            (initialWidth.map(MapNode.validWidth) ?? false) ? initialWidth : nil
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in
            nodes[index].title = title
            if let firstWidth { nodes[index].width = firstWidth }
        }
        guard fitsSavedJSON(updated, relationships: relationships) else { return false }
        save()
        roots = updated
        if !title.isEmpty { pendingInitialWidth.remove(selected) }
        return true
    }

    @discardableResult
    func remove() -> Bool {
        guard selectedIDs.contains(selected), let path = Self.path(to: selected, in: roots) else { return false }
        if path.count == 1 {
            guard roots.count > 1 else { return false }
            save()
            roots.remove(at: path[0])
            relationships = sanitizeRelationships(relationships, nodeIDs: allNodeIDs())
            selected = roots[min(path[0], roots.count - 1)].id
            return true
        }
        let parentID = Self.node(at: path.dropLast(), in: roots).id
        save()
        Self.edit(&roots, at: path[...]) { nodes, index in
            nodes.remove(at: index)
        }
        relationships = sanitizeRelationships(relationships, nodeIDs: allNodeIDs())
        selected = parentID
        return true
    }

    @discardableResult
    func toggleFold() -> Bool {
        guard selectedIDs.contains(selected), let path = Self.path(to: selected, in: roots),
              !Self.node(at: path[...], in: roots).children.isEmpty else { return false }
        var updated = roots
        Self.edit(&updated, at: path[...]) { nodes, index in
            nodes[index].folded.toggle()
        }
        return commit(updated)
    }

    @discardableResult
    func undo() -> Bool {
        guard let previous = past.popLast() else { return false }
        future.append((roots, relationships, theme, canvasColor, selected, selectedIDs, selectionAnchor, pendingInitialWidth))
        (roots, relationships, theme, canvasColor, selected, selectedIDs, selectionAnchor, pendingInitialWidth) = previous
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let next = future.popLast() else { return false }
        past.append((roots, relationships, theme, canvasColor, selected, selectedIDs, selectionAnchor, pendingInitialWidth))
        (roots, relationships, theme, canvasColor, selected, selectedIDs, selectionAnchor, pendingInitialWidth) = next
        return true
    }

    private func selectedPaths() -> [[Int]] {
        selectedIDs.compactMap { Self.path(to: $0, in: roots) }
            .sorted { $0.lexicographicallyPrecedes($1) }
    }

    private func editSelected(_ change: (inout MapNode) -> Void) -> Bool {
        let paths = selectedPaths()
        guard !paths.isEmpty else { return false }
        var updated = roots
        for path in paths {
            Self.edit(&updated, at: path[...]) { nodes, index in change(&nodes[index]) }
        }
        guard updated != roots, fitsSavedJSON(updated, relationships: relationships) else { return false }
        save()
        roots = updated
        return true
    }

    private func commit(_ updated: [MapNode]) -> Bool {
        guard fitsSavedJSON(updated, relationships: relationships) else { return false }
        save()
        roots = updated
        return true
    }

    private func save() {
        past.append((roots, relationships, theme, canvasColor, selected, selectedIDs, selectionAnchor, pendingInitialWidth))
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
