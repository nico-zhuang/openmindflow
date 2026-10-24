import AppKit

private final class MapNodeAX: NSAccessibilityElement {
    weak var canvas: MapCanvas?
    var nodeID: UUID?
    var addsChild = false

    override func accessibilityFrame() -> NSRect {
        guard let canvas, let nodeID else { return super.accessibilityFrame() }
        return (addsChild ? canvas.plusFrameForAccessibility(nodeID) : canvas.frameForAccessibility(nodeID))
            ?? super.accessibilityFrame()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let canvas, let nodeID else { return false }
        if addsChild { canvas.selectNode(nodeID); canvas.addChild() }
        else { canvas.selectAndEdit(nodeID) }
        return true
    }
}

final class MapCanvas: NSView, NSTextFieldDelegate {
    var model: MapModel { didSet { stopSpring(); endEditingWithoutSaving(); revealSelection(); needsDisplay = true } }
    var branchStyles: [UUID: MindNodeVisualStyle] = [:] { didSet { needsDisplay = true } }
    var nativePresentation: [UUID: MindNodePresentation] = [:] { didSet { needsDisplay = true } }
    var embeddedTheme: MindNodeThemeMetadata? { didSet { needsDisplay = true } }
    override var needsDisplay: Bool {
        didSet {
            if springTick || (springTimer != nil && !needsDisplay) { return } // Reuse painted spring frames; preserve old offscreen invalidation.
            previewCache = nil
            let visibleIDs = Set(visibleNodes().map { $0.node.id })
            if needsDisplay, window != nil {
                NSAccessibility.post(element: self, notification: .layoutChanged)
                window?.invalidateCursorRects(for: self)
            }
            for (id, element) in accessibleNodes {
                element.setAccessibilitySelected(model.selectedIDs.contains(id) && visibleIDs.contains(id))
            }
            guard announcedSelection != model.selectedIDs else { return }
            announcedSelection = model.selectedIDs
            NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
            onSelectionChange?()
        }
    }
    var onChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var localizationDefaults: UserDefaults = .standard
    private func t(_ text: String) -> String { L10n.text(text, defaults: localizationDefaults) }
    private var zoom: CGFloat = 1
    private var offset = CGPoint(x: 80, y: 90)
    private var editor: NSTextField?
    private var dragSource: UUID?
    private var dragPoint: CGPoint? { didSet { previewCache = nil } }
    private var dragOrigin: CGPoint?
    private var dragGrab = CGPoint.zero
    private var resize: (id: UUID, startX: CGFloat, startWidth: CGFloat, currentWidth: CGFloat,
                         visibleWidths: [UUID: CGFloat])?
    private var hoveredPlus: Set<UUID> = [] { didSet { if oldValue != hoveredPlus { needsDisplay = true } } }
    private var hoverTracking: NSTrackingArea?
    private var draggedIDs = Set<UUID>()
    private var accessibleNodes: [UUID: MapNodeAX] = [:]
    private var accessiblePlus: [UUID: MapNodeAX] = [:]
    private var previewCache: (nodes: [LaidOutNode], drop: (target: LaidOutNode, parent: UUID, index: Int)?)?
    private var springPositions: [UUID: (point: CGPoint, velocity: CGPoint)] = [:]
    private var springTargets: [UUID: CGPoint] = [:]
    private var springTimer: Timer?
    private var springLastTick: TimeInterval?
    private var springTick = false
    // ponytail: drag-only spring; release/Escape snap until Gate B owns settling and interruption.
    private let springResponse: CGFloat = 0.26, springDamping: CGFloat = 0.95
    private let childOverlapThreshold: CGFloat = 0.65, collisionGap: CGFloat = 8
    private var announcedSelection: Set<UUID>

    init(model: MapModel) {
        self.model = model
        announcedSelection = model.selectedIDs
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view only") }
    deinit { springTimer?.invalidate() }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if editor != nil { revealSelection(); needsDisplay = true }
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        hoverTracking = NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(hoverTracking!)
        super.updateTrackingAreas()
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? {
        let visible = previewGeometry().nodes
        let ids = Set(visible.map { $0.node.id })
        accessibleNodes = accessibleNodes.filter { ids.contains($0.key) }
        let nodes: [MapNodeAX] = visible.map { item in
            let element = accessibleNodes[item.node.id] ?? MapNodeAX()
            accessibleNodes[item.node.id] = element
            element.canvas = self
            element.nodeID = item.node.id
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(item.node.title.isEmpty ? t("New idea") : item.node.title)
            element.setAccessibilityHelp(item.node.children.isEmpty ? nil :
                "\(t(item.node.folded ? "Collapsed" : "Expanded")), \(item.node.children.count) \(t(item.node.children.count == 1 ? "child" : "children"))")
            element.setAccessibilitySelected(model.selectedIDs.contains(item.node.id))
            element.setAccessibilityFrame(window?.convertToScreen(convert(screen(item.frame), to: nil)) ?? .zero)
            return element
        }
        var children: [Any] = nodes
        accessiblePlus = accessiblePlus.filter { hoveredPlus.contains($0.key) }
        for item in visible where hoveredPlus.contains(item.node.id) {
            let button = accessiblePlus[item.node.id] ?? MapNodeAX()
            accessiblePlus[item.node.id] = button
            button.canvas = self
            button.nodeID = item.node.id
            button.addsChild = true
            button.setAccessibilityParent(self)
            button.setAccessibilityRole(.button)
            button.setAccessibilityLabel(t("Add Child"))
            button.setAccessibilityFrame(plusFrameForAccessibility(item.node.id) ?? .zero)
            children.append(button)
        }
        return children + (super.accessibilityChildren() ?? [])
    }

    func plusFrameForAccessibility(_ id: UUID) -> CGRect? {
        guard let item = previewGeometry().nodes.first(where: { $0.node.id == id }) else { return nil }
        let point = plusPoint(item)
        let rect = CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
        return window?.convertToScreen(convert(rect, to: nil)) ?? rect
    }

    func frameForAccessibility(_ id: UUID) -> CGRect? {
        // ponytail: linear UUID lookup per AX element; index the snapshot if large-map VoiceOver navigation stutters.
        guard let item = previewGeometry().nodes.first(where: { $0.node.id == id }) else { return nil }
        let local = screen(item.frame)
        return window?.convertToScreen(convert(local, to: nil)) ?? local
    }

    func selectNode(_ id: UUID) {
        commitEditing()
        guard visibleNodes().contains(where: { $0.node.id == id }) else { return }
        model.selected = id
        revealSelection()
        needsDisplay = true
    }

    func selectAndEdit(_ id: UUID) {
        selectNode(id)
        guard model.selected == id else { return }
        beginEditing()
    }

    private func screen(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX * zoom + offset.x, y: frame.minY * zoom + offset.y,
               width: frame.width * zoom, height: frame.height * zoom)
    }
    func shiftViewport(by delta: CGPoint) {
        guard delta != .zero else { return }
        offset.x += delta.x
        offset.y += delta.y
        if let node = selectedNode() { editor?.frame = editorFrame(node) }
        needsDisplay = true
    }
    private func font(for node: MapNode, isRoot: Bool, zoom: CGFloat = 1) -> NSFont {
        guard !nativePresentation.isEmpty || embeddedTheme != nil else {
            return mapFont(isRoot: isRoot, zoom: zoom, node: node)
        }
        let stored = nativePresentation[node.id]?.font
        let inherited = isRoot ? embeddedTheme?.mainNodes.first?.font : embeddedTheme?.baseSubnode?.font
        let size = CGFloat(node.fontSize ?? stored?.pointSize ?? inherited?.pointSize ?? (isRoot ? 24 : 20)) * zoom
        let family = node.fontFamily ?? stored?.family ?? inherited?.family ?? "STSongti-SC-Regular"
        return NSFont(name: family, size: size)
            ?? NSFont(name: "STSongti-SC-Regular", size: size)
            ?? NSFont.systemFont(ofSize: size)
    }
    private func titleColor(for id: UUID, isRoot: Bool) -> NSColor {
        let inherited = isRoot ? embeddedTheme?.mainNodes.first?.font?.color : embeddedTheme?.baseSubnode?.font?.color
        guard let rgba = nativePresentation[id]?.font?.color ?? inherited, rgba.count == 4 else { return .labelColor }
        let color = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        var background: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            background = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB)
        }
        if !isRoot, let background {
            func lightness(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGFloat {
                0.2126 * red + 0.7152 * green + 0.0722 * blue
            }
            let difference = abs(lightness(CGFloat(rgba[0]), CGFloat(rgba[1]), CGFloat(rgba[2])) -
                                 lightness(background.redComponent, background.greenComponent, background.blueComponent))
            if difference < 0.4 { return .labelColor } // Keep original dark-theme branch text legible on system Light.
        }
        return color
    }
    private func strokeColor(_ hex: String) -> NSColor? {
        guard hex.count == 9, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 24) & 255) / 255,
                       green: CGFloat((value >> 16) & 255) / 255,
                       blue: CGFloat((value >> 8) & 255) / 255,
                       alpha: CGFloat(value & 255) / 255)
    }
    private func plusPoint(_ item: LaidOutNode) -> CGPoint {
        let box = screen(item.frame)
        return CGPoint(x: box.maxX + 15 * zoom,
                       y: item.parent == nil ? box.midY : box.maxY - 7 * zoom)
    }
    private func plusHit(_ point: CGPoint, item: LaidOutNode) -> Bool {
        let center = plusPoint(item)
        return hypot(point.x - center.x, point.y - center.y) <= max(12, 12 * zoom)
    }
    private func selectionBox(_ item: LaidOutNode) -> CGRect {
        screen(item.frame).insetBy(dx: 6 * zoom, dy: 5 * zoom)
    }
    private func resizeHandlePoint(_ item: LaidOutNode) -> CGPoint {
        let box = selectionBox(item)
        return CGPoint(x: box.maxX, y: box.minY)
    }
    private func drawSelectionBox(_ item: LaidOutNode) {
        let path = NSBezierPath(roundedRect: selectionBox(item), xRadius: 4 * zoom, yRadius: 4 * zoom)
        NSColor.controlAccentColor.withAlphaComponent(0.26).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = max(1, zoom)
        path.stroke()
    }
    private func editorFrame(_ node: LaidOutNode) -> CGRect {
        let box = screen(node.frame)
        let width = min(max(120, (node.frame.width - 24) * max(zoom, 0.8)),
                        bounds.width > 128 ? bounds.width - 56 : .greatestFiniteMagnitude)
        let font = font(for: node.node, isRoot: node.parent == nil, zoom: max(zoom, 0.8))
        let textHeight = (node.node.title as NSString).boundingRect(
            with: CGSize(width: width - 8, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
        let height = min(max(22, box.height - 22 * zoom, ceil(textHeight) + 6),
                         max(22, bounds.height - 56))
        // ponytail: the field is viewport-capped; use a scrollable text view if native field-editor scrolling falls short.
        return CGRect(x: box.minX + 12 * zoom,
                      y: node.parent == nil ? box.midY - height / 2 : box.maxY - 9 * zoom - height,
                      width: width, height: height)
    }
    @discardableResult
    func fitMapInView() -> CGRect {
        guard bounds.width > 128, bounds.height > 128 else { return .null }
        let nodes = visibleNodes()
        guard !nodes.isEmpty else { return .null }
        let world = nodes.reduce(CGRect.null) { $0.union($1.frame) }
        zoom = min(1, max(editor == nil ? 0.35 : 0.8,
                          min((bounds.width - 128) / world.width, (bounds.height - 128) / world.height)))
        offset = CGPoint(x: bounds.midX - world.midX * zoom, y: bounds.midY - world.midY * zoom)
        let selected = nodes.first(where: { $0.node.id == model.selected })
        if let selected { editor?.font = font(for: selected.node, isRoot: selected.parent == nil, zoom: max(zoom, 0.8)) }
        editor?.frame = selected.map(editorFrame) ?? .zero
        if editor != nil { revealSelection() }
        needsDisplay = true
        return screen(world)
    }
    private func visibleNodes(for candidate: [MapNode]? = nil) -> [LaidOutNode] {
        // ponytail: copy the tiny tree only during width drag; index nodes if very large maps make resizing lag.
        func preview(_ nodes: [MapNode]) -> [MapNode] {
            nodes.map { item in
                var copy = item
                if let resize, let old = resize.visibleWidths[item.id] {
                    let width = min(1000, max(60, old + resize.currentWidth - resize.startWidth))
                    copy.width = width
                    if copy.location != nil { copy.location!.x += Double(width - old) / 2 }
                }
                copy.children = preview(item.children)
                return copy
            }
        }
        let source = candidate ?? model.roots
        let roots = resize == nil || candidate != nil ? source : preview(source)
        func hasLocation(_ node: MapNode) -> Bool {
            node.location != nil || node.children.contains(where: hasLocation)
        }
        guard !nativePresentation.isEmpty || roots.contains(where: hasLocation) else { return mapLayout(roots) }
        var overrides: [UUID: MapLayoutOverride] = [:]
        func add(_ node: MapNode, isRoot: Bool) {
            let saved = nativePresentation[node.id]
            let width: CGFloat? = saved?.maxWidth.flatMap { value in
                let points = CGFloat(value)
                return MapNode.validWidth(points) ? points : nil
            }
            overrides[node.id] = MapLayoutOverride(location: saved?.location, maxWidth: width,
                allowToShrinkWidth: saved?.allowToShrinkWidth ?? true,
                font: font(for: node, isRoot: isRoot))
            for child in node.children { add(child, isRoot: false) }
        }
        for root in roots { add(root, isRoot: true) }
        return mapLayout(roots, overrides: overrides)
    }
    private func selectedNode() -> LaidOutNode? { visibleNodes().first { $0.node.id == model.selected } }
    private func validDrop(at point: CGPoint, source: UUID, nodes: [LaidOutNode])
        -> (target: LaidOutNode, parent: UUID, index: Int)? {
        let local = CGPoint(x: (point.x - offset.x) / zoom, y: (point.y - offset.y) / zoom)
        if let target = nodes.last(where: { !model.selectedIDs.contains($0.node.id) &&
            screen($0.frame).contains(point) }) {
            let siblings = nodes.filter { $0.parent == target.parent }
            guard var place = dropPlacement(at: local, over: target, siblings: siblings) else { return nil }
            if place.parent == target.node.id, let sourceBox = nodes.first(where: { $0.node.id == source })?.frame {
                let dragged = CGRect(x: (point.x - dragGrab.x - offset.x) / zoom,
                                     y: (point.y - dragGrab.y - offset.y) / zoom,
                                     width: sourceBox.width, height: sourceBox.height)
                let overlap = dragged.intersection(target.frame)
                let fraction = overlap.isNull ? 0 : overlap.width * overlap.height /
                    min(dragged.width * dragged.height, target.frame.width * target.frame.height)
                if fraction < childOverlapThreshold {
                    guard let parent = target.parent,
                          let index = siblings.firstIndex(where: { $0.node.id == target.node.id }) else { return nil }
                    place = (parent, index + (dragged.midY >= target.frame.midY ? 1 : 0))
                }
            }
            guard model.canMoveNode(source, to: place.parent, at: place.index) else { return nil }
            return (target, place.parent, place.index)
        }
        // ponytail: visible sibling gaps only; arbitrary XY needs persisted coordinates and collision layout.
        for siblings in Dictionary(grouping: nodes.filter { $0.parent != nil }, by: { $0.parent! }).values {
            guard let index = siblings.firstIndex(where: { $0.frame.minY > local.y }), index > 0 else { continue }
            let before = siblings[index - 1], after = siblings[index]
            let beforeDistance = local.y - before.frame.maxY, afterDistance = after.frame.minY - local.y
            guard beforeDistance > 0, afterDistance > 0, min(beforeDistance, afterDistance) <= 24,
                  local.x >= min(before.frame.minX, after.frame.minX) - 20,
                  local.x <= max(before.frame.maxX, after.frame.maxX) + 20,
                  model.canMoveNode(source, to: after.parent!, at: index) else { continue }
            return (beforeDistance < afterDistance ? before : after, after.parent!, index)
        }
        return nil
    }
    private func repelNearby(_ nodes: [LaidOutNode], moving: Set<UUID>, childTarget: UUID?) -> [LaidOutNode] {
        guard !moving.isEmpty else { return nodes }
        var frames = Dictionary(uniqueKeysWithValues: nodes.map { ($0.node.id, $0.frame) })
        let dragged = nodes.filter { moving.contains($0.node.id) }.map(\.frame)
        var groups = [Set<UUID>]()
        func subtree(_ node: MapNode) -> Set<UUID> {
            var ids: Set<UUID> = [node.id]
            if !node.folded { node.children.forEach { ids.formUnion(subtree($0)) } }
            return ids
        }
        func group(_ node: MapNode) {
            let ids = subtree(node).intersection(frames.keys)
            if ids.isDisjoint(with: moving) { groups.append(ids) }
            else if !node.folded { node.children.forEach(group) }
        }
        for root in nodes where root.parent == nil && !root.node.folded {
            root.node.children.forEach(group) // Roots stay anchored; each other visible branch moves only as a unit.
        }
        func shift(_ ids: Set<UUID>, _ dy: CGFloat) {
            guard dy != 0 else { return }
            for id in ids { frames[id] = frames[id]!.offsetBy(dx: 0, dy: dy) }
        }
        func separation(_ upper: Set<UUID>, _ lower: Set<UUID>) -> CGFloat {
            var needed: CGFloat = 0
            for a in upper { for b in lower {
                let first = frames[a]!, second = frames[b]!
                if first.minX < second.maxX && first.maxX > second.minX {
                    needed = max(needed, first.maxY + collisionGap - second.minY)
                }
            } }
            return needed
        }
        let movingMidY = dragged.reduce(CGRect.null) { $0.union($1) }.midY
        for ids in groups {
            if let childTarget, ids.contains(childTarget) { continue } // Deliberate large-overlap child hover.
            let box = ids.reduce(CGRect.null) { $0.union(frames[$1]!) }
            let below = box.midY >= movingMidY
            var dy: CGFloat = 0
            for id in ids { for source in dragged {
                let item = frames[id]!
                guard item.minX < source.maxX, item.maxX > source.minX else { continue }
                if below { dy = max(dy, source.maxY + collisionGap - item.minY) }
                else { dy = min(dy, source.minY - collisionGap - item.maxY) }
            } }
            shift(ids, dy)
        }
        // ponytail: bounded pair sweeps can be cubic in branch count; use a spatial index if large maps stutter.
        for _ in 0..<groups.count {
            var changed = false
            for i in groups.indices { for j in groups.indices where j > i {
                let dy = separation(groups[i], groups[j])
                guard dy > 0 else { continue }
                let later = groups[j].reduce(CGRect.null) { $0.union(frames[$1]!) }
                if later.midY < movingMidY { shift(groups[i], -dy) }
                else { shift(groups[j], dy) }
                changed = true
            } }
            if !changed { break }
        }
        return nodes.map { LaidOutNode(node: $0.node, frame: frames[$0.node.id]!, parent: $0.parent) }
    }
    private func pauseSpring() {
        springTimer?.invalidate()
        springTimer = nil
        springLastTick = nil
    }
    private func stopSpring() {
        pauseSpring()
        springPositions.removeAll()
        springTargets.removeAll()
    }
    func advanceSpring(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopSpring(); needsDisplay = true; return
        }
        if previewCache == nil { _ = previewGeometry() }
        guard !springPositions.isEmpty, var cached = previewCache else { return }
        // ponytail: cap stalls at 250ms and integrate in ≤120Hz steps; use display-link timing if long stalls matter.
        let elapsed = min(max(now - (springLastTick ?? now), 0), 0.25)
        springLastTick = now
        guard elapsed > 0 else { return }
        let steps = Int(ceil(elapsed * 120)), dt = CGFloat(elapsed) / CGFloat(steps)
        let omega: CGFloat = 4.6 / springResponse
        for (id, var motion) in springPositions {
            guard let target = springTargets[id] else { continue }
            for _ in 0..<steps {
                motion.velocity.x += ((target.x - motion.point.x) * omega * omega - 2 * springDamping * omega * motion.velocity.x) * dt
                motion.velocity.y += ((target.y - motion.point.y) * omega * omega - 2 * springDamping * omega * motion.velocity.y) * dt
                motion.point.x += motion.velocity.x * dt
                motion.point.y += motion.velocity.y * dt
            }
            if hypot(target.x - motion.point.x, target.y - motion.point.y) < 0.1 &&
               hypot(motion.velocity.x, motion.velocity.y) < 0.5 {
                motion.point = target
            }
            springPositions[id] = motion
        }
        cached.nodes = cached.nodes.map { item in
            guard let point = springPositions[item.node.id]?.point else { return item }
            return LaidOutNode(node: item.node,
                frame: CGRect(origin: point, size: item.frame.size), parent: item.parent)
        }
        let child = cached.drop.flatMap { $0.parent == $0.target.node.id ? $0.parent : nil }
        cached.nodes = repelNearby(cached.nodes, moving: draggedIDs, childTarget: child)
        previewCache = cached
        if springPositions.allSatisfy({ id, motion in motion.point == springTargets[id] }) { pauseSpring() }
        springTick = true; needsDisplay = true; springTick = false
    }
    private func previewGeometry() -> (nodes: [LaidOutNode], drop: (target: LaidOutNode, parent: UUID, index: Int)?) {
        if let previewCache { return previewCache }
        var nodes = visibleNodes()
        let committed = Dictionary(uniqueKeysWithValues: nodes.map { ($0.node.id, $0.frame.origin) })
        draggedIDs.removeAll()
        let drop = dragSource.flatMap { source in
            dragPoint.flatMap { validDrop(at: $0, source: source, nodes: nodes) }
        }
        if let source = dragSource, let point = dragPoint,
           let sourceNode = nodes.first(where: { $0.node.id == source }) {
            var moving = Set<UUID>()
            func collect(_ node: MapNode) {
                moving.insert(node.id)
                if !node.folded { node.children.forEach(collect) }
            }
            for member in nodes where model.selectedIDs.contains(member.node.id) { collect(member.node) }
            draggedIDs = moving
            let sourceBox = screen(sourceNode.frame)
            let dx = (point.x - dragGrab.x - sourceBox.minX) / zoom
            let dy = (point.y - dragGrab.y - sourceBox.minY) / zoom
            let dragged = nodes.filter { moving.contains($0.node.id) }.map {
                LaidOutNode(node: $0.node, frame: $0.frame.offsetBy(dx: dx, dy: dy), parent: $0.parent)
            }
            if let drop {
                // ponytail: O(n) tree copy/layout per drag frame; cache candidate placement or affected branches if large maps stutter.
                let preview = MapModel(roots: model.roots, selected: source)
                for id in model.selectedIDs where id != source { preview.toggleSelection(id) }
                if preview.moveSelectedNodes(to: drop.parent, at: drop.index) {
                    nodes = visibleNodes(for: preview.roots)
                }
            }
            nodes = nodes.filter { !moving.contains($0.node.id) } + dragged
        }
        if drop != nil, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let present = Set(nodes.map { $0.node.id })
            springPositions = springPositions.filter { present.contains($0.key) && !draggedIDs.contains($0.key) }
            springTargets.removeAll()
            for index in nodes.indices {
                let item = nodes[index], id = item.node.id
                guard !draggedIDs.contains(id) else { continue }
                let target = item.frame.origin
                if springPositions[id] == nil, let origin = committed[id], origin != target {
                    springPositions[id] = (origin, .zero)
                }
                if let current = springPositions[id] {
                    springTargets[id] = target
                    nodes[index] = LaidOutNode(node: item.node,
                        frame: CGRect(origin: current.point, size: item.frame.size), parent: item.parent)
                }
            }
            if springTargets.isEmpty { stopSpring() }
            if springTimer == nil, springPositions.contains(where: { $0.value.point != springTargets[$0.key] }) {
                springLastTick = ProcessInfo.processInfo.systemUptime
                let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.advanceSpring() }
                RunLoop.main.add(timer, forMode: .common)
                springTimer = timer
            }
        } else { stopSpring() }
        let child = drop.flatMap { $0.parent == $0.target.node.id ? $0.parent : nil }
        nodes = repelNearby(nodes, moving: draggedIDs, childTarget: child)
        previewCache = (nodes, drop)
        return (nodes, drop)
    }
    private func revealSelection() {
        guard bounds.width > 64, bounds.height > 64, let node = selectedNode() else { return }
        let box = editor == nil ? screen(node.frame) : editorFrame(node), margin: CGFloat = 28
        if box.minX < bounds.minX + margin { offset.x += bounds.minX + margin - box.minX }
        else if box.maxX > bounds.maxX - margin { offset.x -= box.maxX - bounds.maxX + margin }
        if box.height > bounds.height - 2 * margin { offset.y += bounds.minY + margin - box.minY }
        else if box.minY < bounds.minY + margin { offset.y += bounds.minY + margin - box.minY }
        else if box.maxY > bounds.maxY - margin { offset.y -= box.maxY - bounds.maxY + margin }
        editor?.frame = selectedNode().map(editorFrame) ?? .zero
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let (nodes, drop) = previewGeometry()
        if nodes.isEmpty {
            let message = t("Empty map — press Tab to create the first idea.")
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.secondaryLabelColor]
            (message as NSString).draw(at: CGPoint(x: 48, y: 60), withAttributes: attrs)
            return
        }
        // ponytail: fallback palette for own JSON/new nodes; imported v9 nodes use their original pathStyle.
        let palette: [NSColor] = [
            NSColor(srgbRed: 0.945, green: 0.596, blue: 0.290, alpha: 1),
            NSColor(srgbRed: 0.949, green: 0.424, blue: 0.298, alpha: 1),
            NSColor(srgbRed: 0.078, green: 0.620, blue: 0.757, alpha: 1),
            NSColor(srgbRed: 0.063, green: 0.553, blue: 0.545, alpha: 1),
            NSColor(srgbRed: 0.949, green: 0.812, blue: 0.400, alpha: 1)
        ]
        var depth: [UUID: Int] = [:], color: [UUID: NSColor] = [:]
        var branches = 0
        for item in nodes {
            let parentDepth = item.parent.flatMap { depth[$0] } ?? -1
            let level = parentDepth + 1
            depth[item.node.id] = level
            if level == 0 { color[item.node.id] = .secondaryLabelColor }
            else if level == 1 {
                color[item.node.id] = palette[branches % palette.count]
                branches += 1
            } else { color[item.node.id] = item.parent.flatMap { color[$0] } ?? .systemTeal }
            if let rgba = branchStyles[item.node.id]?.rgba, rgba.count == 4 {
                color[item.node.id] = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
            }
            if let hex = item.node.branchStrokeColor, let stroke = strokeColor(hex) {
                color[item.node.id] = stroke
            }
        }
        func strokeWidth(_ item: LaidOutNode) -> CGFloat {
            let fallback: CGFloat = item.parent == nil ? 4 : CGFloat(max(2, 7 - (depth[item.node.id] ?? 1)))
            return max(0.75, (item.node.branchStrokeWidth ?? branchStyles[item.node.id]?.width ?? fallback) * zoom)
        }
        func baseline(_ box: CGRect) -> CGFloat { box.maxY - 7 * zoom }
        for item in nodes {
            guard let parent = nodes.first(where: { $0.node.id == item.parent }) else { continue }
            let start = screen(parent.frame), end = screen(item.frame)
            let line = NSBezierPath()
            let startY = parent.parent == nil ? start.midY : baseline(start)
            line.move(to: CGPoint(x: start.maxX, y: startY))
            line.curve(to: CGPoint(x: end.minX, y: baseline(end)),
                       controlPoint1: CGPoint(x: (start.maxX + end.minX) / 2, y: startY),
                       controlPoint2: CGPoint(x: (start.maxX + end.minX) / 2, y: baseline(end)))
            line.lineWidth = strokeWidth(item)
            line.lineCapStyle = .round
            if item.node.strokeStyle == "dashed" { line.setLineDash([max(8 * zoom, line.lineWidth * 2),
                max(6 * zoom, line.lineWidth * 1.6)], count: 2, phase: 0) }
            (color[item.node.id] ?? .systemTeal).setStroke()
            line.stroke()
        }
        for item in nodes {
            let box = screen(item.frame)
            let hovered = drop?.parent == item.node.id && drop?.target.node.id == item.node.id
            let active = item.node.id == model.selected || hovered
            if item.parent == nil {
                let shape = NSBezierPath(roundedRect: box, xRadius: 9 * zoom, yRadius: 9 * zoom)
                if let rgba = nativePresentation[item.node.id]?.fillColor ?? embeddedTheme?.mainNodes.first?.fillColor,
                   rgba.count == 4 {
                    NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3]).setFill()
                } else { NSColor.controlBackgroundColor.setFill() }
                shape.fill()
                (active ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
                shape.lineWidth = active ? max(2, 2 * zoom) : max(1, zoom)
                shape.stroke()
                if model.selectedIDs.contains(item.node.id) { drawSelectionBox(item) }
            } else {
                if model.selectedIDs.contains(item.node.id) { drawSelectionBox(item) }
                let path = NSBezierPath()
                path.move(to: CGPoint(x: box.minX, y: baseline(box)))
                let lineEnd = item.node.id == model.selected ? max(box.maxX, editor?.frame.maxX ?? box.maxX) : box.maxX
                path.line(to: CGPoint(x: lineEnd, y: baseline(box)))
                path.lineWidth = strokeWidth(item) + (hovered ? 1 : 0)
                path.lineCapStyle = .round
                if item.node.strokeStyle == "dashed" { path.setLineDash([max(8 * zoom, path.lineWidth * 2),
                    max(6 * zoom, path.lineWidth * 1.6)], count: 2, phase: 0) }
                (hovered ? NSColor.controlAccentColor : color[item.node.id] ?? .systemTeal).setStroke()
                path.stroke()
                if hovered {
                    let dot = NSBezierPath(ovalIn: CGRect(x: box.minX - 4 * zoom,
                        y: baseline(box) - 4 * zoom, width: 8 * zoom, height: 8 * zoom))
                    NSColor.controlAccentColor.setFill()
                    dot.fill()
                }
            }
            if editor != nil && item.node.id == model.selected { continue }
            let title = item.node.title.isEmpty ? t("New idea") : item.node.title
            let paragraph = NSMutableParagraphStyle()
            switch item.node.textAlignment ?? nativePresentation[item.node.id]?.font?.alignment ?? "left" {
            case "center": paragraph.alignment = .center
            case "right": paragraph.alignment = .right
            case "justify": paragraph.alignment = .justified
            default: paragraph.alignment = .left
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font(for: item.node, isRoot: item.parent == nil, zoom: zoom),
                .paragraphStyle: paragraph,
                .foregroundColor: item.node.title.isEmpty ? NSColor.secondaryLabelColor : titleColor(for: item.node.id, isRoot: item.parent == nil)
            ]
            let label = item.node.folded && !item.node.children.isEmpty ? "▸ " + title : title
            let height = ceil((label as NSString).boundingRect(
                with: CGSize(width: box.width - 24 * zoom, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs).height)
            let textRect = item.parent == nil
                ? CGRect(x: box.minX + 12 * zoom, y: box.midY - height / 2,
                         width: box.width - 24 * zoom, height: height + 2 * zoom)
                : CGRect(x: box.minX + 12 * zoom, y: baseline(box) - height - 3 * zoom,
                         width: box.width - 24 * zoom, height: height + 2 * zoom)
            (label as NSString).draw(in: textRect, withAttributes: attrs)
            if model.selectedIDs.contains(item.node.id) {
                let point = resizeHandlePoint(item)
                let handle = NSBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5,
                    width: 10, height: 10))
                NSColor.windowBackgroundColor.setFill()
                handle.fill()
                NSColor.controlAccentColor.setStroke()
                handle.lineWidth = max(1.5, 1.5 * zoom)
                handle.stroke()
            }
        }
        for node in nodes where hoveredPlus.contains(node.node.id) && dragSource == nil && editor == nil {
            let center = plusPoint(node)
            let circle = NSBezierPath(ovalIn: CGRect(x: center.x - 9, y: center.y - 9,
                width: 18, height: 18))
            NSColor.controlBackgroundColor.setFill()
            circle.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
            let plus = NSBezierPath()
            plus.move(to: CGPoint(x: center.x - 4, y: center.y))
            plus.line(to: CGPoint(x: center.x + 4, y: center.y))
            plus.move(to: CGPoint(x: center.x, y: center.y - 4))
            plus.line(to: CGPoint(x: center.x, y: center.y + 4))
            plus.lineWidth = 1.5
            plus.stroke()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let nodes = visibleNodes()
        if let item = nodes.first(where: { $0.node.id == model.selected }) {
            let point = resizeHandlePoint(item)
            addCursorRect(CGRect(x: point.x - 11, y: point.y - 11,
                width: 22, height: 22), cursor: .resizeLeftRight)
        }
        for item in nodes where hoveredPlus.contains(item.node.id) {
            let point = plusPoint(item)
            addCursorRect(CGRect(x: point.x - 12, y: point.y - 12,
                width: 24, height: 24), cursor: .pointingHand)
        }
    }

    private func beginEditing() {
        guard editor == nil else { return }
        revealSelection()
        guard let node = selectedNode() else { return }
        if zoom < 0.8 {
            let box = screen(node.frame)
            zoom(at: CGPoint(x: box.midX, y: box.midY), by: 0.8 / zoom)
            revealSelection()
        }
        let field = NSTextField(frame: editorFrame(node))
        field.stringValue = node.node.title
        field.font = font(for: node.node, isRoot: node.parent == nil, zoom: max(zoom, 0.8))
        field.textColor = titleColor(for: node.node.id, isRoot: node.parent == nil)
        switch node.node.textAlignment ?? nativePresentation[node.node.id]?.font?.alignment ?? "left" {
        case "center": field.alignment = .center
        case "right": field.alignment = .right
        case "justify": field.alignment = .justified
        default: field.alignment = .left
        }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
        editor = field
        revealSelection()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        needsDisplay = true
    }

    private func endEditingWithoutSaving() {
        editor?.delegate = nil
        editor?.removeFromSuperview()
        editor = nil
        window?.makeFirstResponder(self)
    }
    func commitEditing() {
        guard let field = editor else { return }
        let title = field.stringValue
        endEditingWithoutSaving()
        if let node = selectedNode(), node.node.title != title {
            let face = font(for: node.node, isRoot: node.parent == nil)
            let longest = title.components(separatedBy: "\n").map {
                ($0 as NSString).size(withAttributes: [.font: face]).width
            }.max() ?? 0
            model.rename(title, initialWidth: min(320, max(60, ceil(longest) + 24)))
            changed()
        } else { needsDisplay = true }
    }
    private func changed() { revealSelection(); needsDisplay = true; onChange?() }
    func addChild() { commitEditing(); model.addChild(); changed(); beginEditing() }
    func addSibling(before: Bool = false) { commitEditing(); let old = model.selected; model.addSibling(before: before); if old != model.selected { changed(); beginEditing() } }
    func addParent() { commitEditing(); let old = model.selected; model.addParent(); if old != model.selected { changed(); beginEditing() } }
    func addMainNode() { commitEditing(); model.addMainNode(); changed(); beginEditing() }
    func detachSelected() { commitEditing(); if model.detachSelected() { changed() } }
    func undo() { commitEditing(); if model.undo() { changed() } }
    func redo() { commitEditing(); if model.redo() { changed() } }
    func toggleFold() { commitEditing(); if model.toggleFold() { changed() } }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertTabIgnoringFieldEditor(_:)) { addParent(); return true }
        if selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) { addSibling(before: true); return true }
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        if selector == #selector(NSResponder.insertTab(_:)) {
            modifiers.contains(.option) ? addParent() : addChild()
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if modifiers.intersection([.shift, .option, .command, .control]).isEmpty { commitEditing() }
            else if modifiers.contains(.shift) { addMainNode() }
            else { addSibling(before: modifiers.contains(.option)) }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) { endEditingWithoutSaving(); needsDisplay = true; return true }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { commitEditing() }

    func contextMenu(for id: UUID?) -> NSMenu {
        if let id { selectNode(id) } else { commitEditing() }
        let menu = NSMenu()
        func add(_ title: String, _ tag: Int) {
            let item = menu.addItem(withTitle: t(title), action: #selector(contextCommand(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
        }
        if let node = visibleNodes().first(where: { $0.node.id == id }) {
            add("Edit Title", 0)
            add("Font…", 16)
            add("New Child", 1)
            if node.parent != nil { add("New Sibling", 2) }
            add("New Main Node", 3)
            if !node.node.children.isEmpty { add("Fold/Unfold", 4) }
            let widthMenu = NSMenu()
            for (index, choice) in ["Auto", "Narrow (170 pt)", "Medium (240 pt)",
                                    "Wide (320 pt)", "Extra Wide (480 pt)"].enumerated() {
                let item = widthMenu.addItem(withTitle: t(choice), action: #selector(contextCommand(_:)), keyEquivalent: "")
                item.target = self
                item.tag = 10 + index
                let width: CGFloat? = index == 0 ? nil : MapNode.widthPresets[index - 1]
                item.state = node.node.width == width ? .on : .off
            }
            let custom = widthMenu.addItem(withTitle: t("Custom Width…"), action: #selector(contextCommand(_:)), keyEquivalent: "")
            custom.target = self
            custom.tag = 15
            menu.addItem(withTitle: t("Node Width"), action: nil, keyEquivalent: "").submenu = widthMenu
            if node.parent != nil || model.roots.count > 1 { add("Delete", 5) }
        } else { add("New Main Node", 3) }
        return menu
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let id = previewGeometry().nodes.last(where: { screen($0.frame).contains(point) })?.node.id
        return contextMenu(for: id)
    }
    @objc private func contextCommand(_ item: NSMenuItem) {
        switch item.tag {
        case 0: beginEditing()
        case 1: addChild()
        case 2: addSibling()
        case 3: addMainNode()
        case 4: toggleFold()
        case 5: commitEditing(); if model.remove() { changed() }
        case 10...14:
            commitEditing()
            let width: CGFloat? = item.tag == 10 ? nil : MapNode.widthPresets[item.tag - 11]
            if model.setWidth(width) { changed() }
        case 16: showFontPanel()
        case 15:
            commitEditing()
            let dialog = NSAlert()
            dialog.messageText = t("Custom Node Width")
            dialog.informativeText = t("Enter a width from 60 to 1000 points.")
            let field = NSTextField(string: String(Int(selectedNode()?.frame.width ?? 170)))
            field.frame = CGRect(x: 0, y: 0, width: 180, height: 24)
            field.setAccessibilityLabel(t("Width in points"))
            dialog.accessoryView = field
            dialog.addButton(withTitle: t("Apply"))
            dialog.addButton(withTitle: t("Cancel"))
            if dialog.runModal() == .alertFirstButtonReturn,
               let value = Double(field.stringValue), model.setWidth(CGFloat(value)) { changed() }
        default: break
        }
    }

    func showFontPanel() {
        commitEditing()
        guard let node = selectedNode() else { return }
        NSFontManager.shared.setSelectedFont(font(for: node.node, isRoot: node.parent == nil), isMultiple: false)
        window?.makeFirstResponder(self)
        NSFontManager.shared.orderFrontFontPanel(self)
    }
    @objc func changeFont(_ manager: NSFontManager) {
        guard let node = selectedNode() else { return }
        let changedFont = manager.convert(font(for: node.node, isRoot: node.parent == nil))
        if model.setFont(family: changedFont.fontName, size: Double(changedFont.pointSize)) { changed() }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.modifierFlags.intersection([.shift, .option, .control]).isEmpty,
               event.charactersIgnoringModifiers?.lowercased() == "n" { addMainNode(); return }
            if !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control),
               [UInt16(125), 126].contains(event.keyCode) {
                commitEditing()
                if model.moveSibling(by: event.keyCode == 126 ? -1 : 1) { changed() }
                return
            }
            if event.charactersIgnoringModifiers?.lowercased() == "d",
               event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) {
                detachSelected()
                return
            }
            if event.charactersIgnoringModifiers?.lowercased() == "z" {
                event.modifierFlags.contains(.shift) ? redo() : undo()
                return
            }
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 53 where dragSource != nil:
            stopSpring(); dragSource = nil; dragPoint = nil; dragOrigin = nil; needsDisplay = true
        case 48 where event.modifierFlags.contains(.option): addParent()
        case 48: addChild()                         // Tab
        case 36, 76:
            if event.modifierFlags.contains(.shift) { addMainNode() }
            else { addSibling(before: event.modifierFlags.contains(.option)) }
        case 51, 117: commitEditing(); if model.remove() { changed() }
        case 49: toggleFold() // Optional Space
        case 47 where event.modifierFlags.contains(.option): toggleFold() // Static original menu: Option+period
        case 123, 124, 125, 126: moveSelection(event.keyCode)
        default:
            if let text = event.characters, !text.isEmpty,
               text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                beginEditing()
                editor?.currentEditor()?.keyDown(with: event)
            } else { super.keyDown(with: event) }
        }
    }

    private func moveSelection(_ key: UInt16) {
        commitEditing()
        let nodes = visibleNodes()
        guard let current = nodes.first(where: { $0.node.id == model.selected }) else { return }
        let target: LaidOutNode?
        switch key {
        case 123: target = nodes.first { $0.node.id == current.parent }
        case 124: target = nodes.first { $0.parent == current.node.id }
        default:
            let direction: CGFloat = key == 125 ? 1 : -1
            target = nodes.filter { ($0.frame.midY - current.frame.midY) * direction > 0 }
                .min { a, b in
                    let aScore = abs(a.frame.midY - current.frame.midY) + abs(a.frame.midX - current.frame.midX) * 2
                    let bScore = abs(b.frame.midY - current.frame.midY) + abs(b.frame.midX - current.frame.midX) * 2
                    return aScore < bScore
                }
        }
        if let target { model.selected = target.node.id; revealSelection(); needsDisplay = true }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let distances: [(UUID, CGFloat)] = visibleNodes().map { item in
            let box = screen(item.frame)
            let dx = max(0, max(box.minX - point.x, point.x - box.maxX))
            let dy = max(0, max(box.minY - point.y, point.y - box.maxY))
            return (item.node.id, hypot(dx, dy))
        }
        let nearby = distances.filter { $0.1 <= 84 }.sorted { $0.1 < $1.1 }.prefix(3)
        hoveredPlus = Set(nearby.map { $0.0 })
    }
    override func mouseExited(with event: NSEvent) { hoveredPlus.removeAll() }

    override func mouseDown(with event: NSEvent) {
        commitEditing()
        let wasPresented = !springPositions.isEmpty
        let hitNodes = wasPresented ? previewGeometry().nodes : visibleNodes()
        stopSpring()
        dragSource = nil
        dragPoint = nil
        resize = nil
        if wasPresented { needsDisplay = true } // A no-hit click must not leave stale spring paint or AX.
        let point = convert(event.locationInWindow, from: nil)
        dragOrigin = point
        if event.clickCount == 1,
           let node = hitNodes.last(where: { plusHit(point, item: $0) }) {
            hoveredPlus.removeAll()
            dragOrigin = nil
            model.selected = node.node.id
            addChild()
            return
        }
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command]).isEmpty,
           let selected = hitNodes.first(where: { model.selectedIDs.contains($0.node.id) &&
               abs(point.x - resizeHandlePoint($0).x) <= 11 &&
               abs(point.y - resizeHandlePoint($0).y) <= 11 }) {
            let widths = Dictionary(uniqueKeysWithValues: hitNodes.filter {
                model.selectedIDs.contains($0.node.id)
            }.map { ($0.node.id, $0.frame.width) })
            resize = (selected.node.id, point.x, selected.frame.width, selected.frame.width, widths)
            needsDisplay = true
            return
        }
        if let node = hitNodes.last(where: { screen($0.frame).contains(point) }) {
            if event.clickCount == 1 && event.modifierFlags.contains(.command) {
                model.toggleSelection(node.node.id)
                dragOrigin = nil
                needsDisplay = true
                return
            }
            if event.clickCount == 1 && event.modifierFlags.contains(.shift) {
                if !model.selectRange(to: node.node.id) { model.toggleSelection(node.node.id) }
                dragOrigin = nil
                needsDisplay = true
                return
            }
            if event.clickCount == 2 || !model.selectedIDs.contains(node.node.id) {
                model.selectOnly(node.node.id)
            }
            dragSource = event.clickCount == 1 && node.parent != nil ? node.node.id : nil
            let box = screen(node.frame)
            dragGrab = CGPoint(x: point.x - box.minX, y: point.y - box.minY)
            needsDisplay = true
            if event.clickCount == 2 { beginEditing() }
        } else { model.selectOnly(model.selected); needsDisplay = true }
        if editor == nil { window?.makeFirstResponder(self) }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if var resize {
            resize.currentWidth = min(1000, max(60, resize.startWidth + (point.x - resize.startX) / zoom))
            self.resize = resize
            needsDisplay = true
            return
        }
        if dragSource != nil {
            if dragPoint == nil, let origin = dragOrigin,
               hypot(point.x - origin.x, point.y - origin.y) < 9 { return }
            dragPoint = point
            needsDisplay = true
            return
        }
        if let origin = dragOrigin {
            offset.x += point.x - origin.x
            offset.y += point.y - origin.y
            dragOrigin = point
            editor?.frame = selectedNode().map(editorFrame) ?? .zero
            needsDisplay = true
        }
    }
    override func mouseUp(with event: NSEvent) {
        defer { stopSpring(); dragSource = nil; dragPoint = nil; dragOrigin = nil; resize = nil; needsDisplay = true }
        if let handle = resize {
            if abs(handle.currentWidth - handle.startWidth) > 0.5,
               model.resizeSelected(by: handle.currentWidth - handle.startWidth,
                    visibleWidths: handle.visibleWidths) { resize = nil; changed() }
            return
        }
        guard let source = dragSource, dragPoint != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let nodes = visibleNodes()
        guard let anchor = nodes.first(where: { $0.node.id == source }) else { return }
        let placement: (target: LaidOutNode, parent: UUID, index: Int)
        if let target = validDrop(at: point, source: source, nodes: nodes) { placement = target }
        else {
            guard model.selectedIDs.count > 1, let parent = anchor.parent,
                  let index = nodes.filter({ $0.parent == parent }).firstIndex(where: { $0.node.id == source })
            else { return }
            placement = (anchor, parent, index)
        }
        let anchorCenter = placement.parent == placement.target.node.id
            ? CGPoint(x: placement.target.frame.maxX + anchor.frame.width / 2 + 60,
                      y: placement.target.frame.midY)
            : CGPoint(x: (point.x - dragGrab.x - offset.x) / zoom + anchor.frame.width / 2,
                      y: (point.y - dragGrab.y - offset.y) / zoom + anchor.frame.height / 2)
        let delta = CGPoint(x: anchorCenter.x - anchor.frame.midX, y: anchorCenter.y - anchor.frame.midY)
        if model.selectedIDs.count > 1 {
            let selected = nodes.filter { model.selectedIDs.contains($0.node.id) }
            let parentByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.node.id, $0.parent) })
            let roots = selected.filter { item in
                var parent = item.parent
                while let id = parent {
                    if model.selectedIDs.contains(id) { return false }
                    parent = parentByID[id] ?? nil
                }
                return true
            }
            let coordinates: [UUID: CGPoint]? = roots.contains(where: { $0.node.location != nil }) ?
                Dictionary(uniqueKeysWithValues: roots.map {
                    ($0.node.id, CGPoint(x: $0.frame.midX + delta.x, y: $0.frame.midY + delta.y))
                }) : nil
            if model.moveSelectedNodes(to: placement.parent, at: placement.index,
                                       locations: coordinates) { changed() }
        } else if model.moveNode(source, to: placement.parent, at: placement.index,
                                 location: anchor.node.location == nil ? nil : anchorCenter) { changed() }
    }
    private func zoom(at point: CGPoint, by factor: CGFloat) {
        let next = min(3, max(editor == nil ? 0.35 : 0.8, zoom * factor))
        offset.x = point.x - (point.x - offset.x) * next / zoom
        offset.y = point.y - (point.y - offset.y) * next / zoom
        zoom = next
        let selected = selectedNode()
        if let selected { editor?.font = font(for: selected.node, isRoot: selected.parent == nil, zoom: max(zoom, 0.8)) }
        editor?.frame = selected.map(editorFrame) ?? .zero
        needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            zoom(at: convert(event.locationInWindow, from: nil), by: exp(event.scrollingDeltaY * 0.01))
        } else {
            offset.x += event.scrollingDeltaX
            offset.y += event.scrollingDeltaY
            editor?.frame = selectedNode().map(editorFrame) ?? .zero
            needsDisplay = true
        }
    }
    override func magnify(with event: NSEvent) {
        zoom(at: convert(event.locationInWindow, from: nil), by: 1 + event.magnification)
    }
}

#if HEADLESS_TEST
private func ownedPanelFixtureDirectory() -> URL? {
    guard let path = ProcessInfo.processInfo.environment["MINDMAP_SELFTEST_PANEL_DIR"] else { return nil }
    let directory = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
    guard directory.lastPathComponent.hasPrefix("mindmap-native-panel-"),
          (try? String(contentsOf: directory.appendingPathComponent(".owner"), encoding: .utf8)) == "mindmap-owned-native-panel\n",
          attributes?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid()),
          (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { return nil }
    return directory
}
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSOpenSavePanelDelegate, NSToolbarDelegate {
    private var window: NSWindow!
    private var canvas: MapCanvas!
    private var outline: MapOutlineView!
    private var inspector: StyleInspector!
    private var splitController: NSSplitViewController!
    private var fileURL: URL?
    private var savedRoots: [MapNode] = []
    private var dirty = false
    private var closeApproved = false
    private var settingsWindow: NSWindow?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }
    private func t(_ english: String) -> String { L10n.text(english, defaults: defaults) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = MapNode(id: UUID(), title: t("Central idea"), children: [], folded: false)
        canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        savedRoots = [root]
        _ = makeWorkbench(canvas: canvas)
        canvas.onChange = { [weak self] in
            self?.syncDirty(); self?.outline.reloadMap(); self?.inspector.refresh()
        }
        canvas.onSelectionChange = { [weak self] in
            self?.outline.syncSelection(); self?.inspector.refresh()
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "\(t("Untitled")) — \(t("MindMap"))"
        window.delegate = self
        window.minSize = NSSize(width: 640, height: 400)
        window.contentViewController = splitController
        window.toolbar = makeToolbar()
        window.center()
        installMenu()
        window.contentView?.layoutSubtreeIfNeeded()
        canvas.fitMapInView()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard confirmDiscardOrSave() else { return false }
        closeApproved = true
        NSApp.terminate(nil) // Exit the single-window app instead of stranding its map.
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        closeApproved || confirmDiscardOrSave() ? .terminateNow : .terminateCancel
    }
    private func syncDirty() {
        // ponytail: O(nodes) comparison per edit; use revision IDs if large-map editing becomes slow.
        dirty = canvas.model.roots != savedRoots
        updateTitle()
    }
    private func updateTitle() { window.title = "\(fileURL?.lastPathComponent ?? t("Untitled"))\(dirty ? " •" : "") — \(t("MindMap"))" }
    private func alert(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = t(message)
        alert.informativeText = t(detail)
        alert.alertStyle = .warning
        alert.runModal()
    }
    private func confirmDiscardOrSave() -> Bool {
        canvas.commitEditing()
        guard dirty else { return true }
        let prompt = NSAlert()
        prompt.messageText = t("Save changes to this map?")
        prompt.informativeText = t("Opening another file, closing the window, or quitting will discard unsaved changes.")
        prompt.addButton(withTitle: t("Save"))
        prompt.addButton(withTitle: t("Cancel"))
        prompt.addButton(withTitle: t("Discard Changes"))
        switch prompt.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    @objc private func openFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        #if HEADLESS_TEST
        guard let directory = ownedPanelFixtureDirectory() else { return }
        panel.directoryURL = directory
        #endif
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        #if HEADLESS_TEST
        guard url.resolvingSymlinksInPath() == directory.appendingPathComponent("Untitled.mindmap.json") else { return }
        #endif
        guard url.lastPathComponent.hasSuffix(".mindmap.json") else {
            alert("Unsupported format", detail: "Select an existing .mindmap.json file; use Open MindNode for a read-only import.")
            return
        }
        do {
            _ = try readOwnJSON(url) // Reject invalid files without prompting to discard edits.
            guard confirmDiscardOrSave() else { return }
            // Saving may have changed this same path; never install the pre-save tree.
            let roots = try readOwnJSON(url)
            canvas.model = MapModel(roots: roots, selected: roots.first?.id ?? UUID())
            canvas.branchStyles = [:]
            canvas.nativePresentation = [:]
            canvas.embeddedTheme = nil
            outline.reloadMap()
            fileURL = url
            savedRoots = roots
            dirty = false
            updateTitle()
            canvas.fitMapInView()
            window.makeFirstResponder(canvas)
        } catch { alert("Could not open map", detail: error.localizedDescription) }
    }
    @objc private func openMindNode(_ sender: Any?) {
        let panel = NSOpenPanel()
        #if HEADLESS_TEST
        guard let directory = ownedPanelFixtureDirectory() else { return }
        panel.directoryURL = directory
        #endif
        // The installed MindNode UTType conforms to .data, not .package or .directory.
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.delegate = self
        panel.message = t("Select a MindNode v9 binary-plist file or directory package. Import is read-only; Save creates a new .mindmap.json file.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        #if HEADLESS_TEST
        guard ["fixture.mindnode", "single.mindnode"].contains(url.lastPathComponent),
              url.resolvingSymlinksInPath().deletingLastPathComponent() == directory else { return }
        #endif
        do {
            let imported = try MindNodeImporter.loadDetailed(url)
            guard confirmDiscardOrSave() else { return }
            canvas.model = MapModel(roots: imported.roots, selected: imported.roots.first?.id ?? UUID())
            canvas.branchStyles = imported.styles
            canvas.embeddedTheme = imported.theme
            canvas.nativePresentation = imported.presentation
            outline.reloadMap()
            fileURL = nil // Never save into the source package.
            savedRoots = imported.roots
            dirty = false
            updateTitle()
            canvas.fitMapInView()
            window.makeFirstResponder(canvas)
        } catch { alert("Could not open MindNode", detail: error.localizedDescription) }
    }
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let kind = (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType
        return kind == .typeDirectory || (kind == .typeRegular && url.pathExtension.lowercased() == "mindnode")
    }
    func panel(_ sender: Any, validate url: URL) throws {
        let kind = (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType
        guard url.pathExtension.lowercased() == "mindnode",
              kind == .typeDirectory || kind == .typeRegular else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnsupportedSchemeError,
                          userInfo: [NSLocalizedDescriptionKey: t("Select a .mindnode v9 binary-plist file or directory package.")])
        }
    }
    @objc private func saveFile(_ sender: Any?) { _ = save() }
    private func save() -> Bool {
        canvas.commitEditing()
        var destination = fileURL
        if destination == nil {
            let panel = NSSavePanel()
            #if HEADLESS_TEST
            guard let directory = ownedPanelFixtureDirectory() else { return false }
            panel.directoryURL = directory
            #endif
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Untitled.mindmap.json"
            guard panel.runModal() == .OK else { return false }
            destination = panel.url
        }
        guard let url = destination, url.lastPathComponent.hasSuffix(".mindmap.json") else {
            alert("Unsupported format", detail: "Save only as .mindmap.json; original .mindnode documents cannot be overwritten.")
            return false
        }
        #if HEADLESS_TEST
        guard let directory = ownedPanelFixtureDirectory(),
              url.standardizedFileURL == directory.appendingPathComponent("Untitled.mindmap.json").standardizedFileURL else { return false }
        #endif
        do {
            #if HEADLESS_TEST
            if ProcessInfo.processInfo.environment["MINDMAP_PANEL_ACTION"] == "save-failure" { throw POSIXError(.EIO) }
            #endif
            try writeOwnJSON(canvas.model.roots, to: url)
            fileURL = url
            savedRoots = canvas.model.roots
            dirty = false
            updateTitle()
            return true
        } catch {
            alert("Could not save map", detail: error.localizedDescription)
            return false
        }
    }
    @objc private func undoEdit(_ sender: Any?) { canvas.undo() }
    @objc private func redoEdit(_ sender: Any?) { canvas.redo() }
    @objc private func newChild(_ sender: Any?) { canvas.addChild() }
    @objc private func newSibling(_ sender: Any?) { canvas.addSibling() }
    @objc private func newSiblingBefore(_ sender: Any?) { canvas.addSibling(before: true) }
    @objc private func newParent(_ sender: Any?) { canvas.addParent() }
    @objc private func newMainNode(_ sender: Any?) { canvas.addMainNode() }
    @objc private func detachNode(_ sender: Any?) { canvas.detachSelected() }
    @objc private func foldNode(_ sender: Any?) { canvas.toggleFold() }
    @objc private func showNodeFont(_ sender: Any?) { canvas.showFontPanel() }
    @objc private func fitMap(_ sender: Any?) { canvas.fitMapInView() }
    private func togglePane(at index: Int) {
        let window = splitController.view.window
        let frame = window?.frame
        let host = window?.contentView
        let oldOrigin = host.map { canvas.convert(CGPoint.zero, to: $0) }
        let item = splitController.splitViewItems[index]
        item.isCollapsed.toggle()
        if let frame, window?.frame != frame { window?.setFrame(frame, display: true) }
        host?.layoutSubtreeIfNeeded()
        if let oldOrigin, let host {
            let newOrigin = canvas.convert(CGPoint.zero, to: host)
            canvas.shiftViewport(by: CGPoint(x: oldOrigin.x - newOrigin.x, y: oldOrigin.y - newOrigin.y))
        }
        if item.isCollapsed { window?.makeFirstResponder(canvas) }
    }
    @objc private func toggleOutline(_ sender: Any?) { togglePane(at: 0) }
    @objc private func toggleStyle(_ sender: Any?) { togglePane(at: 2) }

    func makeWorkbench(canvas: MapCanvas) -> NSSplitViewController {
        self.canvas = canvas
        canvas.localizationDefaults = defaults
        let split = NSSplitViewController()
        let sidebarController = NSViewController()
        outline = MapOutlineView(canvas: canvas, defaults: defaults)
        sidebarController.view = outline
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebar.canCollapse = true
        sidebar.minimumThickness = 180
        sidebar.maximumThickness = 320
        split.addSplitViewItem(sidebar)
        let canvasController = NSViewController()
        canvasController.view = canvas
        split.addSplitViewItem(NSSplitViewItem(viewController: canvasController))
        let inspectorController = NSViewController()
        inspector = StyleInspector(canvas: canvas, defaults: defaults)
        inspectorController.view = inspector
        let style = NSSplitViewItem(viewController: inspectorController)
        style.canCollapse = true
        style.minimumThickness = 260
        style.maximumThickness = 320
        style.holdingPriority = .defaultHigh
        split.addSplitViewItem(style)
        split.preferredContentSize = NSSize(width: 1280, height: 700)
        splitController = split
        return split
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MindMap")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        return toolbar
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("new-main"), .init("new-child"), .init("new-sibling"), .init("fold-node"), .init("fit-map"),
         .init("outline"), .flexibleSpace, .init("style"), .init("undo"), .init("redo")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let details: (String, String, Selector)
        switch identifier.rawValue {
        case "new-main": details = ("New Main Node", "plus.square.on.square", #selector(newMainNode(_:)))
        case "new-child": details = ("New Child", "plus", #selector(newChild(_:)))
        case "new-sibling": details = ("New Sibling", "arrow.turn.down.right", #selector(newSibling(_:)))
        case "fold-node": details = ("Fold/Unfold", "chevron.right", #selector(foldNode(_:)))
        case "fit-map": details = ("Fit Map", "arrow.up.left.and.arrow.down.right", #selector(fitMap(_:)))
        case "outline": details = ("Show/Hide Outline", "sidebar.left", #selector(toggleOutline(_:)))
        case "style": details = ("Show/Hide Style", "sidebar.right", #selector(toggleStyle(_:)))
        case "undo": details = ("Undo", "arrow.uturn.backward", #selector(undoEdit(_:)))
        case "redo": details = ("Redo", "arrow.uturn.forward", #selector(redoEdit(_:)))
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = t(details.0)
        item.paletteLabel = item.label
        item.toolTip = item.label
        item.image = NSImage(systemSymbolName: details.1, accessibilityDescription: item.label)
        item.target = self
        item.action = details.2
        return item
    }

    private func applyAppearance(_ mode: String, in menu: NSMenu) {
        let selected = ["light", "dark"].contains(mode) ? mode : "system"
        NSApp.appearance = selected == "system" ? nil : NSAppearance(named: selected == "light" ? .aqua : .darkAqua)
        for item in menu.items { item.state = (item.representedObject as? String) == selected ? .on : .off }
    }
    @objc private func chooseAppearance(_ sender: NSMenuItem) {
        guard let menu = sender.menu else { return }
        let mode = sender.representedObject as? String ?? ""
        guard ["system", "light", "dark"].contains(mode) else { return }
        defaults.set(mode, forKey: "appearance")
        applyAppearance(mode, in: menu)
    }

    @objc private func showSettings(_ sender: Any?) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 390, height: 120),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let label = NSTextField(labelWithString: t("Interface Language"))
        label.frame = CGRect(x: 18, y: 56, width: 130, height: 22)
        let popup = NSPopUpButton(frame: CGRect(x: 148, y: 52, width: 224, height: 28), pullsDown: false)
        for (key, name) in [("system", "Follow System"), ("zh-Hans", "Simplified Chinese"), ("en", "English")] {
            let item = popup.menu!.addItem(withTitle: t(name), action: nil, keyEquivalent: "")
            item.representedObject = key
        }
        popup.select(popup.itemArray.first { ($0.representedObject as? String) == L10n.choice(defaults: defaults) }!)
        popup.setAccessibilityLabel(t("Interface Language"))
        popup.target = self
        popup.action = #selector(chooseLanguage(_:))
        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(popup)
        panel.title = t("Settings")
        panel.center()
        settingsWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func chooseLanguage(_ sender: NSPopUpButton) {
        guard let chosen = sender.selectedItem?.representedObject as? String,
              L10n.setLanguage(chosen, defaults: defaults) else { return }
        installMenu()
        outline?.localize()
        inspector?.localize()
        canvas?.needsDisplay = true
        if window != nil { updateTitle() }
        if let toolbar = window?.toolbar {
            for item in toolbar.items {
                guard let translated = self.toolbar(toolbar, itemForItemIdentifier: item.itemIdentifier,
                                                     willBeInsertedIntoToolbar: false) else { continue }
                item.label = translated.label
                item.paletteLabel = translated.paletteLabel
                item.toolTip = translated.toolTip
                item.image = translated.image
            }
        }
        settingsWindow?.title = t("Settings")
        if let label = settingsWindow?.contentView?.subviews.compactMap({ $0 as? NSTextField }).first {
            label.stringValue = t("Interface Language")
        }
        sender.setAccessibilityLabel(t("Interface Language"))
        for item in sender.itemArray {
            switch item.representedObject as? String {
            case "system": item.title = t("Follow System")
            case "zh-Hans": item.title = t("Simplified Chinese")
            case "en": item.title = t("English")
            default: break
            }
        }
    }

    func installMenu() {
        let main = NSMenu()
        let app = NSMenuItem(title: t("MindMap"), action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: t("Settings…"), action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: t("Quit MindMap"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        main.addItem(app)
        let file = NSMenuItem(title: t("File"), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: t("File"))
        let readOnlyOpen = fileMenu.addItem(withTitle: t("Open MindNode (Read-only)…"), action: #selector(openMindNode(_:)), keyEquivalent: "o")
        readOnlyOpen.keyEquivalentModifierMask = [.command, .shift]
        readOnlyOpen.target = self
        fileMenu.addItem(withTitle: t("Open Own JSON…"), action: #selector(openFile(_:)), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: t("Save"), action: #selector(saveFile(_:)), keyEquivalent: "s").target = self
        file.submenu = fileMenu
        main.addItem(file)
        let edit = NSMenuItem(title: t("Edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: t("Edit"))
        editMenu.addItem(withTitle: t("Undo"), action: #selector(undoEdit(_:)), keyEquivalent: "z").target = self
        let redo = editMenu.addItem(withTitle: t("Redo"), action: #selector(redoEdit(_:)), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = self
        editMenu.addItem(withTitle: t("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: t("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: t("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: t("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        main.addItem(edit)
        let view = NSMenuItem(title: t("View"), action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: t("View"))
        let outlineItem = viewMenu.addItem(withTitle: t("Show/Hide Outline"),
            action: #selector(toggleOutline(_:)), keyEquivalent: "s")
        outlineItem.keyEquivalentModifierMask = [.option, .command]
        outlineItem.target = self
        let styleItem = viewMenu.addItem(withTitle: t("Show/Hide Style Inspector"),
            action: #selector(toggleStyle(_:)), keyEquivalent: "i")
        styleItem.keyEquivalentModifierMask = [.option, .command]
        styleItem.target = self
        let appearanceItem = NSMenuItem(title: t("Appearance"), action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: t("Appearance"))
        for title in ["System", "Light", "Dark"] {
            let item = appearanceMenu.addItem(withTitle: t(title), action: #selector(chooseAppearance(_:)), keyEquivalent: "")
            item.representedObject = title.lowercased()
            item.target = self
        }
        appearanceItem.submenu = appearanceMenu
        viewMenu.addItem(appearanceItem)
        view.submenu = viewMenu
        main.addItem(view)
        let node = NSMenuItem(title: t("Node"), action: nil, keyEquivalent: "")
        let nodeMenu = NSMenu(title: t("Node"))
        let entries: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("New Child", #selector(newChild(_:)), "\t", []),
            ("New Sibling", #selector(newSibling(_:)), "", []),
            ("New Sibling Before", #selector(newSiblingBefore(_:)), "\r", [.option]),
            ("New Parent", #selector(newParent(_:)), "\t", [.option]),
            ("New Main Node", #selector(newMainNode(_:)), "n", [.command]),
            ("Detach Node", #selector(detachNode(_:)), "D", [.command, .shift])
        ]
        for (title, action, key, modifiers) in entries {
            let item = nodeMenu.addItem(withTitle: t(title), action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
        }
        nodeMenu.addItem(withTitle: t("Font…"), action: #selector(showNodeFont(_:)), keyEquivalent: "t").target = self
        node.submenu = nodeMenu
        main.addItem(node)
        NSApp.mainMenu = main
        applyAppearance(defaults.string(forKey: "appearance") ?? "system", in: appearanceMenu)
    }
}

#if !HEADLESS_TEST
@main
enum MindMapApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
#endif
