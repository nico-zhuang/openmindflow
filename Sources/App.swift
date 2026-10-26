import AppKit
import ImageIO
import UniformTypeIdentifiers

// World or screen rectangles use the same coordinate space; only the caller supplies the zoomed inset.
func branchConnectorEndpoints(parent: CGRect, child: CGRect, parentIsRoot: Bool,
                              goesLeft: Bool, baselineInset: CGFloat) -> (start: CGPoint, end: CGPoint, controlX: CGFloat) {
    let end = CGPoint(x: goesLeft ? child.maxX : child.minX, y: child.maxY - baselineInset)
    // Follow a left first-level underline along the root edge. Clamp near its
    // corners so dragging a branch across the edge never snaps the trunk.
    let rootLeftY = parent.height > 2 * baselineInset
        ? min(max(end.y, parent.minY + baselineInset), parent.maxY - baselineInset)
        : parent.midY
    let start = CGPoint(x: goesLeft ? parent.minX : parent.maxX,
                        y: parentIsRoot ? (goesLeft ? rootLeftY : parent.midY) : parent.maxY - baselineInset)
    return (start, end, (start.x + end.x) / 2)
}

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
        guard canvas.selectNode(nodeID) else { return false }
        if addsChild { canvas.addChild() }
        else { canvas.selectAndEdit(nodeID) }
        return true
    }
}

private enum NodeShortcuts {
    static let commands: [(id: String, title: String, key: String)] = [
        ("new-child", "New Child", "tab"), ("new-sibling", "New Sibling", "return"),
        ("new-sibling-before", "New Sibling Before", "option-return"),
        ("new-main", "New Main Node", "shift-return"),
        ("new-parent", "New Parent", "option-tab"), ("edit-title", "Edit Title", "command-return")
    ]
    static let choices: [(key: String, code: UInt16, modifiers: NSEvent.ModifierFlags, label: String)] = [
        ("tab", 48, [], "Tab"), ("return", 36, [], "Return"),
        ("option-return", 36, .option, "Option + Return"),
        ("shift-return", 36, .shift, "Shift + Return"),
        ("option-tab", 48, .option, "Option + Tab"),
        ("command-return", 36, .command, "Command + Return"),
        ("control-tab", 48, .control, "Control + Tab"),
        ("control-return", 36, .control, "Control + Return"),
        ("control-shift-tab", 48, [.control, .shift], "Control + Shift + Tab"),
        ("control-shift-return", 36, [.control, .shift], "Control + Shift + Return"),
        ("option-shift-return", 36, [.option, .shift], "Option + Shift + Return"),
        ("command-shift-return", 36, [.command, .shift], "Command + Shift + Return")
    ]
    static func bindings(_ defaults: UserDefaults) -> [String: String] {
        let fallback = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0.key) })
        guard let saved = defaults.dictionary(forKey: "nodeShortcuts") as? [String: String],
              saved.count == commands.count, Set(saved.keys) == Set(fallback.keys),
              Set(saved.values).count == saved.count,
              saved.values.allSatisfy({ key in choices.contains { $0.key == key } }) else { return fallback }
        return saved
    }
    static func set(_ command: String, key: String, defaults: UserDefaults) -> Bool {
        guard commands.contains(where: { $0.id == command }), choices.contains(where: { $0.key == key }) else { return false }
        var saved = bindings(defaults)
        guard !saved.contains(where: { $0.key != command && $0.value == key }) else { return false }
        saved[command] = key
        defaults.set(saved, forKey: "nodeShortcuts")
        return true
    }
    static func command(code: UInt16, modifiers: NSEvent.ModifierFlags,
                        defaults: UserDefaults) -> String? {
        let normalized = code == 76 ? UInt16(36) : code
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        guard let key = choices.first(where: { $0.code == normalized && $0.modifiers == flags })?.key else { return nil }
        return bindings(defaults).first(where: { $0.value == key })?.key
    }
}

final class MapCanvas: NSView, NSTextFieldDelegate {
    var model: MapModel { didSet { let alreadyReplacing = replacingModel; replacingModel = true; stopSpring(); endEditingWithoutSaving(); stopVideo(); videoPosters.removeAllObjects(); selectedRelationshipID = nil; relationshipColorPanelID = nil; revealSelection(); needsDisplay = true; replacingModel = alreadyReplacing } }
    var replacingModel = false
    private(set) var selectedRelationshipID: UUID? {
        didSet { if oldValue != selectedRelationshipID && !replacingModel { onSelectionChange?() } }
    }
    private var relationshipColorPanelID: UUID?
    var branchStyles: [UUID: MindNodeVisualStyle] = [:] { didSet { needsDisplay = true } }
    var nativePresentation: [UUID: MindNodePresentation] = [:] { didSet { needsDisplay = true } }
    var embeddedTheme: MindNodeThemeMetadata? { didSet { needsDisplay = true } }
    override var needsDisplay: Bool {
        didSet {
            if springTick || (springTimer != nil && !needsDisplay) { return } // Reuse painted spring frames; preserve old offscreen invalidation.
            previewCache = nil
            let visible = visibleNodes()
            let visibleIDs = Set(visible.map { $0.node.id })
            if let playing = videoPlayer {
                if let node = visible.first(where: { $0.node.id == playing.id }),
                   let rect = videoRect(node) { playing.view.frame = rect }
                else { stopVideo() }
            }
            if needsDisplay, window != nil {
                NSAccessibility.post(element: self, notification: .layoutChanged)
                window?.invalidateCursorRects(for: self)
            }
            for (id, element) in accessibleNodes {
                element.setAccessibilitySelected(model.selectedIDs.contains(id) && visibleIDs.contains(id))
            }
            if replacingModel { return }
            guard announcedSelection != model.selectedIDs else { return }
            announcedSelection = model.selectedIDs
            NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
            onSelectionChange?()
        }
    }
    var onChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onBeforeCommit: (() -> Bool)?
    var onEditNote: ((UUID) -> Void)?
    var onImageError: ((Error) -> Void)?
    var onVideoError: ((Error) -> Void)?
    var localizationDefaults: UserDefaults = .standard
    private func t(_ text: String) -> String { L10n.text(text, defaults: localizationDefaults) }
    private var zoom: CGFloat = 1
    private var offset = CGPoint(x: 80, y: 90)
    private var editor: NSTextField?
    private var videoPlayer: (id: UUID, view: MapVideoPlayerView)?
    private let videoPosters = NSCache<NSUUID, NSImage>()
    private var dragSource: UUID?
    private var relationshipDrag: (id: UUID, first: Bool, grab: CGPoint, point: CGPoint)?
    private var dragPoint: CGPoint? { didSet { previewCache = nil } }
    private var dragOrigin: CGPoint?
    private var dragGrab = CGPoint.zero
    private var handTool = false
    private var middlePanning = false
    private var marquee: CGRect?
    private var blankPastePoint: CGPoint?
    private static let groupPasteboardType = NSPasteboard.PasteboardType("local.mindmap.node-group.v1")
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
        videoPosters.totalCostLimit = 128 * 1024 * 1024
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
            let title = item.node.title.isEmpty
                ? t(item.node.video != nil ? "Video" : item.node.image != nil ? "Image" : "New idea")
                : item.node.title
            let hasNote = item.node.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            element.setAccessibilityLabel(hasNote ? "\(title), \(t("Has note"))" : title)
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
        let point = plusPoint(item, among: previewGeometry().nodes)
        let rect = CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
        return window?.convertToScreen(convert(rect, to: nil)) ?? rect
    }

    func frameForAccessibility(_ id: UUID) -> CGRect? {
        // ponytail: linear UUID lookup per AX element; index the snapshot if large-map VoiceOver navigation stutters.
        guard let item = previewGeometry().nodes.first(where: { $0.node.id == id }) else { return nil }
        let local = screen(item.frame)
        return window?.convertToScreen(convert(local, to: nil)) ?? local
    }
    private func imageRect(_ item: LaidOutNode) -> CGRect? {
        guard let image = item.node.image else { return nil }
        let box = screen(item.frame)
        let width = min(image.displaySize(width: item.node.imageWidth).width, item.frame.width - 24)
        let size = image.displaySize(width: max(1, width))
        return CGRect(x: box.minX + 12 * zoom, y: box.minY + 11 * zoom,
                      width: size.width * zoom, height: size.height * zoom)
    }
    private func videoRect(_ item: LaidOutNode) -> CGRect? {
        guard let video = item.node.video else { return nil }
        let box = screen(item.frame)
        let width = min(video.displaySize(width: item.node.videoWidth).width, item.frame.width - 24)
        let size = video.displaySize(width: max(1, width))
        return CGRect(x: box.minX + 12 * zoom, y: box.minY + 11 * zoom,
                      width: size.width * zoom, height: size.height * zoom)
    }
    func mediaRect(for id: UUID) -> CGRect? {
        guard let item = previewGeometry().nodes.first(where: { $0.node.id == id }) else { return nil }
        return videoRect(item) ?? imageRect(item)
    }
    func mediaTitleRect(for id: UUID) -> CGRect? {
        guard let item = previewGeometry().nodes.first(where: { $0.node.id == id }),
              let media = videoRect(item) ?? imageRect(item) else { return nil }
        let box = screen(item.frame)
        let face = font(for: item.node, isRoot: item.parent == nil, zoom: zoom)
        let height = ceil((item.node.title as NSString).boundingRect(
            with: CGSize(width: box.width - 24 * zoom, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: face]).height)
        return CGRect(x: box.minX + 12 * zoom, y: media.maxY + 8 * zoom,
                      width: box.width - 24 * zoom, height: height + 2 * zoom)
    }
    private func stopVideo() {
        guard let playing = videoPlayer else { return }
        videoPlayer = nil
        playing.view.player?.pause()
        playing.view.removeFromSuperview()
    }
    @discardableResult
    func playVideo(_ id: UUID) -> Bool {
        if videoPlayer?.id == id { return true }
        guard let item = visibleNodes().first(where: { $0.node.id == id }),
              let video = item.node.video, let frame = videoRect(item) else { return false }
        do {
            let view = try MapVideoPlayerView(video: video)
            stopVideo()
            view.frame = frame
            addSubview(view)
            videoPlayer = (id, view)
            view.player?.play()
            return true
        } catch { onVideoError?(error); return false }
    }
    func imageFrameForAccessibility(_ id: UUID) -> CGRect? {
        guard let item = previewGeometry().nodes.first(where: { $0.node.id == id }),
              let local = imageRect(item) else { return nil }
        return window?.convertToScreen(convert(local, to: nil)) ?? local
    }

    @objc override func selectAll(_ sender: Any?) {
        guard commitEditing() else { return }
        selectedRelationshipID = nil
        if model.selectNodes(Set(visibleNodes().map(\.node.id))) { needsDisplay = true }
    }
    @discardableResult
    func selectNode(_ id: UUID) -> Bool {
        guard commitEditing(), visibleNodes().contains(where: { $0.node.id == id }) else { return false }
        selectedRelationshipID = nil
        model.selected = id
        revealSelection()
        needsDisplay = true
        return true
    }

    func selectAndEdit(_ id: UUID) {
        guard selectNode(id) else { return }
        beginEditing()
    }
    func showSearchResult(_ id: UUID) {
        guard commitEditing() else { return }
        selectedRelationshipID = nil
        let expanded = model.revealSearchResult(id)
        if expanded { changed() }
        else { revealSelection(); needsDisplay = true }
    }

    private func screen(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX * zoom + offset.x, y: frame.minY * zoom + offset.y,
               width: frame.width * zoom, height: frame.height * zoom)
    }
    private func screen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * zoom + offset.x, y: point.y * zoom + offset.y)
    }
    private func world(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / zoom, y: (point.y - offset.y) / zoom)
    }
    private func relationGeometry(_ edge: MapRelationship, nodes: [LaidOutNode]) -> RelationshipGeometry? {
        guard let from = nodes.first(where: { $0.node.id == edge.from }),
              let to = nodes.first(where: { $0.node.id == edge.to }) else { return nil }
        var preview = edge
        if let drag = relationshipDrag, drag.id == edge.id {
            let point = world(drag.point)
            let node = drag.first ? from.frame : to.frame
            let other = drag.first ? to.frame : from.frame
            let aim = SIMD2(Double(point.x - node.midX), Double(point.y - node.midY))
            let toward = aim == .zero ? CGPoint(x: other.midX, y: other.midY) : point
            guard let anchor = relationshipAnchor(in: node, toward: toward) else { return nil }
            let offset = SIMD2(Double(point.x - anchor.x), Double(point.y - anchor.y))
            if drag.first { preview.control1Aim = aim; preview.control1 = offset }
            else { preview.control2Aim = aim; preview.control2 = offset }
        }
        return relationshipGeometry(preview, from: from.frame, to: to.frame)
    }
    private func relationAt(_ screenPoint: CGPoint, nodes: [LaidOutNode]) -> UUID? {
        let point = world(screenPoint)
        for edge in model.relationships.reversed() {
            guard let curve = relationGeometry(edge, nodes: nodes) else { continue }
            var previous = curve.start
            for step in 1...32 {
                let t = CGFloat(step) / 32, u = 1 - t
                let next = CGPoint(x: u*u*u*curve.start.x + 3*u*u*t*curve.control1.x +
                    3*u*t*t*curve.control2.x + t*t*t*curve.end.x,
                    y: u*u*u*curve.start.y + 3*u*u*t*curve.control1.y +
                    3*u*t*t*curve.control2.y + t*t*t*curve.end.y)
                let dx = next.x - previous.x, dy = next.y - previous.y
                let projection = max(0, min(1, ((point.x - previous.x)*dx + (point.y - previous.y)*dy) / max(1, dx*dx + dy*dy)))
                if hypot(point.x - previous.x - projection*dx, point.y - previous.y - projection*dy) <= 9 / zoom {
                    return edge.id
                }
                previous = next
            }
        }
        return nil
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
    private func composite(_ foreground: NSColor, over background: NSColor) -> NSColor {
        let front = foreground.usingColorSpace(.deviceRGB)!, back = background.usingColorSpace(.deviceRGB)!
        let alpha = front.alphaComponent
        return NSColor(srgbRed: front.redComponent * alpha + back.redComponent * (1 - alpha),
                       green: front.greenComponent * alpha + back.greenComponent * (1 - alpha),
                       blue: front.blueComponent * alpha + back.blueComponent * (1 - alpha), alpha: 1)
    }
    private var canvasBackground: NSColor {
        var system = NSColor.windowBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            system = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? .windowBackgroundColor
        }
        let imported = embeddedTheme?.backgroundColor.flatMap { rgba -> NSColor? in
            guard rgba.count == 4 else { return nil }
            return NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        }
        let themed = InspectorTheme(rawValue: model.theme ?? "")?.canvasBackground.flatMap(strokeColor)
        return composite(model.canvasColor.flatMap(strokeColor) ?? themed ?? imported ?? system, over: system)
    }
    private func rootFill(for node: MapNode) -> NSColor {
        if let hex = node.rootFillColor ?? InspectorTheme(rawValue: model.theme ?? "")?.rootFill,
           let color = strokeColor(hex) { return color }
        if let rgba = nativePresentation[node.id]?.fillColor ?? embeddedTheme?.mainNodes.first?.fillColor,
           rgba.count == 4 { return NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3]) }
        return .controlBackgroundColor
    }
    private func titleColor(for node: MapNode, isRoot: Bool, placeholder: Bool = false) -> NSColor {
        let inherited = isRoot ? embeddedTheme?.mainNodes.first?.font?.color : embeddedTheme?.baseSubnode?.font?.color
        let rgba = nativePresentation[node.id]?.font?.color ?? inherited
        let theme = InspectorTheme(rawValue: model.theme ?? "")
        let themedTitle = (isRoot ? theme?.rootTitleColor : theme?.branchTitleColor).flatMap(strokeColor)
        let candidate: NSColor = rgba?.count == 4
            ? NSColor(srgbRed: rgba![0], green: rgba![1], blue: rgba![2], alpha: rgba![3])
            : (placeholder ? .secondaryLabelColor : themedTitle ?? .labelColor)
        let background = isRoot ? composite(rootFill(for: node), over: canvasBackground) : canvasBackground
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = color.usingColorSpace(.sRGB)!
            let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { value in
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let foreground = luminance(composite(candidate, over: background))
        let backdrop = luminance(background)
        if (max(foreground, backdrop) + 0.05) / (min(foreground, backdrop) + 0.05) >= 4.5 { return candidate }
        return backdrop > 0.179 ? .black : .white
    }
    private func strokeColor(_ hex: String) -> NSColor? {
        guard hex.count == 9, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 24) & 255) / 255,
                       green: CGFloat((value >> 16) & 255) / 255,
                       blue: CGFloat((value >> 8) & 255) / 255,
                       alpha: CGFloat(value & 255) / 255)
    }
    private func goesLeft(_ item: LaidOutNode, among nodes: [LaidOutNode]) -> Bool {
        guard item.parent != nil else { return false }
        var branch = item
        while let parentID = branch.parent, let parent = nodes.first(where: { $0.node.id == parentID }) {
            if parent.parent == nil {
                if let side = branch.node.branchSide { return side == "left" }
                // Imported nil-side positions can be on either side of the root; infer from real layout.
                return branch.frame.midX < parent.frame.midX
            }
            branch = parent
        }
        return false
    }
    private func plusPoint(_ item: LaidOutNode, among nodes: [LaidOutNode]) -> CGPoint {
        let box = screen(item.frame)
        return CGPoint(x: goesLeft(item, among: nodes) ? box.minX - 15 * zoom : box.maxX + 15 * zoom,
                       y: item.parent == nil ? box.midY : box.maxY - 7 * zoom)
    }
    private func plusHit(_ point: CGPoint, item: LaidOutNode, among nodes: [LaidOutNode]) -> Bool {
        let center = plusPoint(item, among: nodes)
        return hypot(point.x - center.x, point.y - center.y) <= max(12, 12 * zoom)
    }
    private func selectionBox(_ item: LaidOutNode) -> CGRect {
        screen(item.frame).insetBy(dx: 6 * zoom, dy: 5 * zoom)
    }
    private func resizeHandlePoint(_ item: LaidOutNode, among nodes: [LaidOutNode]) -> CGPoint {
        if model.selectedIDs.count == 1, let media = imageRect(item) ?? videoRect(item) {
            return CGPoint(x: media.maxX, y: media.maxY)
        }
        let box = selectionBox(item)
        return CGPoint(x: goesLeft(item, among: nodes) ? box.minX : box.maxX, y: box.minY)
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
        let noteInset: CGFloat = node.parent == nil &&
            node.node.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 24 * zoom : 0
        let width = min(max(noteInset > 0 ? 48 : 120,
                            (node.frame.width - 24) * max(zoom, 0.8) - noteInset),
                        bounds.width > 128 ? bounds.width - 56 : .greatestFiniteMagnitude)
        let font = font(for: node.node, isRoot: node.parent == nil, zoom: max(zoom, 0.8))
        let textHeight = (node.node.title as NSString).boundingRect(
            with: CGSize(width: width - 8, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
        let height = min(node.node.image == nil && node.node.video == nil
                             ? max(22, box.height - 22 * zoom, ceil(textHeight) + 6)
                             : max(22, ceil(textHeight) + 6),
                         max(22, bounds.height - 56))
        // ponytail: the field is viewport-capped; use a scrollable text view if native field-editor scrolling falls short.
        // At 60pt a 48pt field cannot fit between the inset and paper. Extend it left instead of covering the icon.
        let leadingX = noteInset > 0 ? min(box.minX + 12 * zoom, box.maxX - 23.25 * zoom - width)
                                     : box.minX + 12 * zoom
        return CGRect(x: leadingX,
                      y: (imageRect(node) ?? videoRect(node)).map { $0.maxY + 8 * zoom }
                           ?? (node.parent == nil ? box.midY - height / 2 : box.maxY - 9 * zoom - height),
                      width: width, height: height)
    }
    @discardableResult
    func fitMapInView() -> CGRect {
        guard bounds.width > 128, bounds.height > 128 else { return .null }
        let nodes = visibleNodes()
        guard !nodes.isEmpty else { return .null }
        var world = nodes.reduce(CGRect.null) { $0.union($1.frame) }
        for edge in model.relationships {
            guard let curve = relationGeometry(edge, nodes: nodes) else { continue }
            for point in [curve.start, curve.control1, curve.control2, curve.end] +
                (curve.startArrowhead ?? []) + (curve.endArrowhead ?? []) {
                world = world.union(CGRect(origin: point, size: .zero))
            }
        }
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
        let source = candidate ?? model.roots
        let baseline = resize == nil || candidate != nil ? [] : visibleNodes(for: source)
        let leftIDs = Set(baseline.filter { goesLeft($0, among: baseline) }.map { $0.node.id })
        let baselineCenters = Dictionary(uniqueKeysWithValues: baseline.map {
            ($0.node.id, CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        })
        func preview(_ nodes: [MapNode], ancestorShift: Double = 0) -> [MapNode] {
            nodes.map { item in
                var copy = item
                var shift = ancestorShift
                if let resize, let old = resize.visibleWidths[item.id] {
                    let delta = resize.currentWidth - resize.startWidth
                    if model.selectedIDs.count == 1, let image = copy.image {
                        copy.imageWidth = min(1000, max(60, image.displaySize(width: copy.imageWidth).width + delta))
                    } else if model.selectedIDs.count == 1, let video = copy.video {
                        copy.videoWidth = min(1000, max(60, video.displaySize(width: copy.videoWidth).width + delta))
                    } else {
                        let width = min(1000, max(60, old + delta))
                        copy.width = width
                        shift += Double(width - old) * (leftIDs.contains(item.id) ? -1 : 1)
                        let half = Double(width - old) * (leftIDs.contains(item.id) ? -0.5 : 0.5)
                        if copy.location == nil, let center = baselineCenters[item.id] {
                            copy.location = SIMD2(Double(center.x) + half, Double(center.y))
                        } else { copy.location?.x += half }
                    }
                }
                if ancestorShift != 0 {
                    if copy.location == nil, let center = baselineCenters[item.id] {
                        copy.location = SIMD2(Double(center.x) + ancestorShift, Double(center.y))
                    } else { copy.location?.x += ancestorShift }
                }
                copy.children = preview(item.children, ancestorShift: shift)
                return copy
            }
        }
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
        canvasBackground.setFill()
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
        let theme = InspectorTheme(rawValue: model.theme ?? "")
        var branches = 0
        for item in nodes {
            let parentDepth = item.parent.flatMap { depth[$0] } ?? -1
            let level = parentDepth + 1
            depth[item.node.id] = level
            if level == 0 { color[item.node.id] = .secondaryLabelColor }
            else if level == 1 {
                color[item.node.id] = theme.flatMap { strokeColor($0.branchColors[branches % $0.branchColors.count]) }
                    ?? palette[branches % palette.count]
                branches += 1
            } else { color[item.node.id] = item.parent.flatMap { color[$0] } ?? .systemTeal }
            if theme == nil, let rgba = branchStyles[item.node.id]?.rgba, rgba.count == 4 {
                color[item.node.id] = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
            }
            if level == 1, item.node.branchStrokeColor == nil,
               let root = nodes.first(where: { $0.node.id == item.parent }),
               let hex = root.node.branchStrokeColor, let stroke = strokeColor(hex) {
                color[item.node.id] = stroke
            }
            if let hex = item.node.branchStrokeColor, let stroke = strokeColor(hex) {
                color[item.node.id] = stroke
            }
        }
        func rootStyle(_ item: LaidOutNode) -> MapNode? {
            guard depth[item.node.id] == 1 else { return nil }
            return nodes.first(where: { $0.node.id == item.parent })?.node
        }
        func strokeWidth(_ item: LaidOutNode) -> CGFloat {
            let fallback: CGFloat = item.parent == nil ? 4 : CGFloat(max(2, 7 - (depth[item.node.id] ?? 1)))
            return max(0.75, (item.node.branchStrokeWidth ?? rootStyle(item)?.branchStrokeWidth ?? branchStyles[item.node.id]?.width ?? fallback) * zoom)
        }
        func dashed(_ item: LaidOutNode) -> Bool {
            (item.node.strokeStyle ?? rootStyle(item)?.strokeStyle) == "dashed"
        }
        func baseline(_ box: CGRect) -> CGFloat { box.maxY - 7 * zoom }
        for item in nodes {
            guard let parent = nodes.first(where: { $0.node.id == item.parent }) else { continue }
            let points = branchConnectorEndpoints(parent: screen(parent.frame), child: screen(item.frame),
                parentIsRoot: parent.parent == nil, goesLeft: goesLeft(item, among: nodes), baselineInset: 7 * zoom)
            let line = NSBezierPath()
            line.move(to: points.start)
            line.curve(to: points.end,
                       controlPoint1: CGPoint(x: points.controlX, y: points.start.y),
                       controlPoint2: CGPoint(x: points.controlX, y: points.end.y))
            line.lineWidth = strokeWidth(item)
            line.lineCapStyle = .round
            if dashed(item) { line.setLineDash([max(8 * zoom, line.lineWidth * 2),
                max(6 * zoom, line.lineWidth * 1.6)], count: 2, phase: 0) }
            (color[item.node.id] ?? .systemTeal).setStroke()
            line.stroke()
        }
        for edge in model.relationships {
            guard let geometry = relationGeometry(edge, nodes: nodes) else { continue }
            let path = NSBezierPath()
            path.move(to: screen(geometry.start))
            path.curve(to: screen(geometry.end), controlPoint1: screen(geometry.control1),
                       controlPoint2: screen(geometry.control2))
            path.lineWidth = max(1.5, zoom * (selectedRelationshipID == edge.id ? 3 : 2))
            path.lineCapStyle = .round
            switch edge.style {
            case .solid: break
            case .dashed: path.setLineDash([8 * zoom, 5 * zoom], count: 2, phase: 0)
            case .dotted: path.setLineDash([1 * zoom, 5 * zoom], count: 2, phase: 0)
            }
            (edge.color.flatMap(strokeColor) ?? .systemPurple).set()
            path.stroke()
            for head in [geometry.startArrowhead, geometry.endArrowhead].compactMap({ $0 }) {
                let arrow = NSBezierPath()
                arrow.move(to: screen(head[0]))
                arrow.line(to: screen(head[1]))
                arrow.line(to: screen(head[2]))
                arrow.close()
                arrow.fill()
            }
            if selectedRelationshipID == edge.id {
                let guides = NSBezierPath()
                guides.move(to: screen(geometry.start))
                guides.line(to: screen(geometry.control1))
                guides.move(to: screen(geometry.end))
                guides.line(to: screen(geometry.control2))
                guides.lineWidth = 1.5
                NSColor.controlAccentColor.setStroke()
                guides.stroke()
                for point in [geometry.control1, geometry.control2] {
                    let center = screen(point)
                    let handle = NSBezierPath(ovalIn: CGRect(x: center.x - 6, y: center.y - 6,
                                                             width: 12, height: 12))
                    NSColor.windowBackgroundColor.setFill()
                    handle.fill()
                    NSColor.controlAccentColor.setStroke()
                    handle.lineWidth = 2
                    handle.stroke()
                }
            }
        }
        func drawNote(for item: LaidOutNode, in box: CGRect) {
            guard let text = item.node.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            // Child paper sits beyond the underline; root paper stays inside the filled shape.
            let x = item.parent == nil ? box.maxX - 22 * zoom :
                (goesLeft(item, among: nodes) ? box.minX - 20 * zoom : box.maxX + 8 * zoom)
            let y = item.parent == nil ? box.midY - 6 * zoom : baseline(box) - 25 * zoom
            let paper = NSBezierPath()
            paper.move(to: CGPoint(x: x, y: y))
            paper.line(to: CGPoint(x: x + 8 * zoom, y: y))
            paper.line(to: CGPoint(x: x + 12 * zoom, y: y + 4 * zoom))
            paper.line(to: CGPoint(x: x + 12 * zoom, y: y + 12 * zoom))
            paper.line(to: CGPoint(x: x, y: y + 12 * zoom))
            paper.close()
            paper.move(to: CGPoint(x: x + 8 * zoom, y: y))
            paper.line(to: CGPoint(x: x + 8 * zoom, y: y + 4 * zoom))
            paper.line(to: CGPoint(x: x + 12 * zoom, y: y + 4 * zoom))
            for row in [7, 9] {
                paper.move(to: CGPoint(x: x + 3 * zoom, y: y + CGFloat(row) * zoom))
                paper.line(to: CGPoint(x: x + 9 * zoom, y: y + CGFloat(row) * zoom))
            }
            paper.lineWidth = max(1, 1.25 * zoom)
            paper.lineJoinStyle = .round
            NSColor.controlAccentColor.setStroke()
            paper.stroke()
        }
        for item in nodes {
            let box = screen(item.frame)
            let hovered = drop?.parent == item.node.id && drop?.target.node.id == item.node.id
            let active = item.node.id == model.selected || hovered
            if item.parent == nil {
                let radius: CGFloat = item.node.rootShape == "rectangle" ? 0 : 9 * zoom
                let shape = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
                rootFill(for: item.node).setFill()
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
                if dashed(item) { path.setLineDash([max(8 * zoom, path.lineWidth * 2),
                    max(6 * zoom, path.lineWidth * 1.6)], count: 2, phase: 0) }
                (hovered ? NSColor.controlAccentColor : color[item.node.id] ?? .systemTeal).setStroke()
                path.stroke()
                if hovered {
                    let connectionX = goesLeft(item, among: nodes) ? box.maxX : box.minX
                    let dot = NSBezierPath(ovalIn: CGRect(x: connectionX - 4 * zoom,
                        y: baseline(box) - 4 * zoom, width: 8 * zoom, height: 8 * zoom))
                    NSColor.controlAccentColor.setFill()
                    dot.fill()
                }
            }
            if let rect = imageRect(item), let data = item.node.image?.data,
               let image = NSImage(data: data) {
                image.draw(in: rect, from: .zero, operation: .sourceOver,
                           fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
            if let rect = videoRect(item), let clip = item.node.video {
                let poster = videoPosters.object(forKey: item.node.id as NSUUID) ?? clip.posterImage()
                if let poster {
                    videoPosters.setObject(poster, forKey: item.node.id as NSUUID,
                                           cost: clip.pixelWidth * clip.pixelHeight * 4)
                    poster.draw(in: rect, from: .zero, operation: .sourceOver,
                                fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                }
                if videoPlayer?.id != item.node.id {
                    NSColor.black.withAlphaComponent(0.7).setFill()
                    NSBezierPath(ovalIn: CGRect(x: rect.midX - 18, y: rect.midY - 18, width: 36, height: 36)).fill()
                    NSColor.white.setFill()
                    let play = NSBezierPath()
                    play.move(to: CGPoint(x: rect.midX - 5, y: rect.midY - 9))
                    play.line(to: CGPoint(x: rect.midX + 11, y: rect.midY))
                    play.line(to: CGPoint(x: rect.midX - 5, y: rect.midY + 9))
                    play.close()
                    play.fill()
                }
            }
            if editor != nil && item.node.id == model.selected {
                drawNote(for: item, in: box)
                continue // The live title editor replaces only the painted title, not the note.
            }
            let title = item.node.title.isEmpty ? (item.node.image == nil && item.node.video == nil ? t("New idea") : "") : item.node.title
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
                .foregroundColor: titleColor(for: item.node, isRoot: item.parent == nil, placeholder: item.node.title.isEmpty)
            ]
            let label = item.node.folded && !item.node.children.isEmpty ? "▸ " + title : title
            let noteSpace: CGFloat = item.parent == nil &&
                item.node.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 24 * zoom : 0
            let height = ceil((label as NSString).boundingRect(
                with: CGSize(width: max(1, box.width - 24 * zoom - noteSpace), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs).height)
            let textRect = item.node.image != nil || item.node.video != nil
                ? CGRect(x: box.minX + 12 * zoom,
                         y: ((imageRect(item) ?? videoRect(item))?.maxY ?? box.minY) + 8 * zoom,
                         width: box.width - 24 * zoom - noteSpace, height: height + 2 * zoom)
                : item.parent == nil
                    ? CGRect(x: box.minX + 12 * zoom, y: box.midY - height / 2,
                             width: box.width - 24 * zoom - noteSpace, height: height + 2 * zoom)
                    : CGRect(x: box.minX + 12 * zoom, y: baseline(box) - height - 3 * zoom,
                             width: box.width - 24 * zoom, height: height + 2 * zoom)
            (label as NSString).draw(in: textRect, withAttributes: attrs)
            drawNote(for: item, in: box)
            if model.selectedIDs.contains(item.node.id) {
                let point = resizeHandlePoint(item, among: nodes)
                let handle = NSBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5,
                    width: 10, height: 10))
                NSColor.windowBackgroundColor.setFill()
                handle.fill()
                NSColor.controlAccentColor.setStroke()
                handle.lineWidth = max(1.5, 1.5 * zoom)
                handle.stroke()
            }
        }
        if let marquee {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: marquee).fill()
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: marquee)
            border.lineWidth = 1
            border.setLineDash([4, 3], count: 2, phase: 0)
            border.stroke()
        }
        for node in nodes where hoveredPlus.contains(node.node.id) && dragSource == nil && editor == nil && !handTool {
            let center = plusPoint(node, among: nodes)
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
        if handTool || middlePanning {
            addCursorRect(bounds, cursor: middlePanning ? .closedHand : .openHand)
            return
        }
        let nodes = visibleNodes()
        if let item = nodes.first(where: { $0.node.id == model.selected }) {
            let point = resizeHandlePoint(item, among: nodes)
            addCursorRect(CGRect(x: point.x - 11, y: point.y - 11,
                width: 22, height: 22), cursor: .resizeLeftRight)
        }
        for item in nodes where hoveredPlus.contains(item.node.id) {
            let point = plusPoint(item, among: nodes)
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
        field.textColor = titleColor(for: node.node, isRoot: node.parent == nil)
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
    @discardableResult
    func commitEditing() -> Bool {
        guard onBeforeCommit?() ?? true else { return false }
        guard let field = editor else { return true }
        let title = field.stringValue
        if let node = selectedNode(), node.node.title != title {
            let face = font(for: node.node, isRoot: node.parent == nil)
            let longest = title.components(separatedBy: "\n").map {
                ($0 as NSString).size(withAttributes: [.font: face]).width
            }.max() ?? 0
            let compact = localizationDefaults.object(forKey: "shrinkNewNodesToFitContent") == nil ||
                localizationDefaults.bool(forKey: "shrinkNewNodesToFitContent")
            guard model.rename(title, initialWidth: compact ? min(320, max(60, ceil(longest) + 24)) : nil) else {
                if let window = field.window, window.firstResponder !== field,
                   window.firstResponder !== field.currentEditor() {
                    field.delegate = nil // Avoid reentrant controlTextDidEndEditing while returning focus.
                    _ = window.makeFirstResponder(field)
                    field.delegate = self
                }
                return false
            }
            endEditingWithoutSaving()
            changed()
        } else { endEditingWithoutSaving(); needsDisplay = true }
        return true
    }
    private func changed(reveal: Bool = true) {
        if let id = selectedRelationshipID, !model.relationships.contains(where: { $0.id == id }) {
            selectedRelationshipID = nil
        }
        if reveal { revealSelection() }
        needsDisplay = true; onChange?()
    }
    func addChild() { guard commitEditing() else { return }; let old = model.selected; model.addChild(); if old != model.selected { changed(); beginEditing() } }
    func addSibling(before: Bool = false) { guard commitEditing() else { return }; let old = model.selected; model.addSibling(before: before); if old != model.selected { changed(); beginEditing() } }
    func addParent() { guard commitEditing() else { return }; let old = model.selected; model.addParent(); if old != model.selected { changed(); beginEditing() } }
    func addMainNode() { guard commitEditing() else { return }; let old = model.selected; model.addMainNode(); if old != model.selected { changed(); beginEditing() } }
    func insertImageData(_ data: Data) throws {
        let image = try MapImage(data: data)
        guard commitEditing() else { throw OwnJSONError.tooLarge }
        guard model.addImageChild(image) else { throw OwnJSONError.tooLarge }
        changed()
    }
    func insertVideoData(_ data: Data) throws {
        let video = try MapVideo(data: data)
        guard commitEditing() else { throw OwnJSONError.tooLarge }
        guard model.addVideoChild(video) else { throw OwnJSONError.tooLarge }
        changed()
    }
    func insertVideoFile(_ url: URL) throws {
        guard url.isFileURL, ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) else {
            throw MapVideoError.invalidFormat
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: MapVideo.maxEmbeddedBytes + 1 - data.count), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= MapVideo.maxEmbeddedBytes else { throw MapVideoError.tooLarge }
        }
        try insertVideoData(data)
    }
    @discardableResult
    func pasteVideoFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        do {
            if let file = pasteboard.string(forType: .fileURL), let url = URL(string: file) {
                try insertVideoFile(url)
            } else if let data = ["public.mpeg-4", "com.apple.quicktime-movie", "public.m4v"]
                        .compactMap({ pasteboard.data(forType: .init($0)) }).first {
                try insertVideoData(data)
            } else { return false }
            return true
        } catch { onVideoError?(error); return false }
    }
    @discardableResult
    func pasteImageFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .init("public.jpeg"), .init("public.heic"), .init("public.heif")]
        do {
            if let data = imageTypes.compactMap({ pasteboard.data(forType: $0) }).first {
                try insertImageData(data)
            } else if let tiff = pasteboard.data(forType: .tiff) {
                guard tiff.count <= 8 * 1024 * 1024 else { throw MapImageError.tooLarge }
                guard let source = CGImageSourceCreateWithData(tiff as CFData, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = props[kCGImagePropertyPixelWidth] as? Int,
                      let height = props[kCGImagePropertyPixelHeight] as? Int,
                      (1...4096).contains(width), (1...4096).contains(height),
                      width * height <= 16_000_000 else { throw MapImageError.invalidDimensions }
                guard let image = NSBitmapImageRep(data: tiff),
                      let data = image.representation(using: .png, properties: [:]) else {
                    throw MapImageError.invalidData
                }
                try insertImageData(data)
            } else { return false }
            return true
        } catch { onImageError?(error); return false }
    }
    @discardableResult
    func copySelection(to pasteboard: NSPasteboard) -> Bool {
        guard commitEditing() else { return false }
        let centers = Dictionary(uniqueKeysWithValues: visibleNodes().map {
            ($0.node.id, CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        })
        guard let clip = model.copySelection(visibleCenters: centers),
              let data = try? JSONEncoder().encode(clip) else { return false }
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: Self.groupPasteboardType)
    }
    @objc func copy(_ sender: Any?) { _ = copySelection(to: .general) }

    @discardableResult
    func pasteSelection(from pasteboard: NSPasteboard, at point: CGPoint) -> Bool {
        guard let data = pasteboard.data(forType: Self.groupPasteboardType),
              data.count <= MapModel.maxSavedJSONBytes,
              let clip = try? JSONDecoder().decode(MapSelectionClip.self, from: data) else { return false }
        guard commitEditing() else { return false }
        let world = CGPoint(x: (point.x - offset.x) / zoom, y: (point.y - offset.y) / zoom)
        guard model.pasteSelection(clip, at: world) else { return false }
        changed()
        return true
    }
    @objc func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if board.availableType(from: [Self.groupPasteboardType]) != nil {
            _ = pasteSelection(from: board, at: blankPastePoint ?? CGPoint(x: bounds.midX, y: bounds.midY))
            return
        }
        if board.availableType(from: [.png, .init("public.jpeg"), .init("public.heic"),
                                      .init("public.heif"), .tiff]) != nil {
            _ = pasteImageFromPasteboard(board)
        } else if board.availableType(from: [.fileURL, .init("public.mpeg-4"),
                                               .init("com.apple.quicktime-movie"), .init("public.m4v")]) != nil {
            _ = pasteVideoFromPasteboard(board)
        } else if let text = board.string(forType: .string) {
            beginEditing()
            editor?.currentEditor()?.insertText(text)
        }
    }
    func detachSelected() { guard commitEditing() else { return }; if model.detachSelected() { changed() } }
    func undo() { guard commitEditing() else { return }; if model.undo() { changed() } }
    func redo() { guard commitEditing() else { return }; if model.redo() { changed() } }
    func toggleFold() { guard commitEditing() else { return }; if model.toggleFold() { changed() } }

    private func performNodeShortcut(_ command: String) -> Bool {
        switch command {
        case "new-child": addChild()
        case "new-sibling": addSibling()
        case "new-sibling-before": addSibling(before: true)
        case "new-main": addMainNode()
        case "new-parent": addParent()
        case "edit-title": if editor == nil { beginEditing() } else { _ = commitEditing() }
        default: return false
        }
        return true
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let fallback: (UInt16, NSEvent.ModifierFlags)
        switch selector {
        case #selector(NSResponder.insertTabIgnoringFieldEditor(_:)): fallback = (48, .option)
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)): fallback = (36, .option)
        case #selector(NSResponder.insertTab(_:)): fallback = (48, [])
        case #selector(NSResponder.insertNewline(_:)): fallback = (36, [])
        case #selector(NSResponder.cancelOperation(_:)):
            endEditingWithoutSaving(); needsDisplay = true; return true
        default: return false
        }
        let event = NSApp.currentEvent.flatMap { [UInt16(48), 36, 76].contains($0.keyCode) ? $0 : nil }
        let code = event?.keyCode ?? fallback.0
        let modifiers = event?.modifierFlags ?? fallback.1
        let action = NodeShortcuts.command(code: code, modifiers: modifiers, defaults: localizationDefaults)
        if action == "new-sibling" && code != 48 &&
            modifiers.intersection([.shift, .option, .command, .control]).isEmpty {
            commitEditing() // First plain Return completes the active editor; second creates a sibling.
            return true
        }
        if let action { return performNodeShortcut(action) }
        if code != 48 && modifiers.intersection([.shift, .option, .command, .control]).isEmpty {
            commitEditing()
            return true
        }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { commitEditing() }

    func arrangeMap() {
        guard commitEditing() else { return }
        func unfolded(_ nodes: [MapNode]) -> [MapNode] {
            nodes.map { node in
                var copy = node
                copy.folded = false
                copy.children = unfolded(node.children)
                return copy
            }
        }
        let positions = Dictionary(uniqueKeysWithValues: mapLayout(unfolded(model.roots)).map {
            ($0.node.id, CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        })
        if model.arrange(at: positions) { changed(); _ = fitMapInView() }
    }
    func contextMenu(for id: UUID?) -> NSMenu {
        if let id, !model.selectedIDs.contains(id) {
            guard selectNode(id) else { return NSMenu() }
        } else { guard commitEditing() else { return NSMenu() } }
        guard editor == nil else { return NSMenu() }
        if id != nil { selectedRelationshipID = nil }
        let menu = NSMenu()
        func add(_ title: String, _ tag: Int) {
            let item = menu.addItem(withTitle: t(title), action: #selector(contextCommand(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
        }
        if let node = visibleNodes().first(where: { $0.node.id == id }) {
            if model.selectedIDs.count == 2 { add("Create Relationship", 30) }
            add("Edit Title", 0)
            add("Edit Note", 37)
            add("Copy", 21)
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
            if let parentID = node.parent, visibleNodes().first(where: { $0.node.id == parentID })?.parent == nil {
                for (side, tag) in [("left", 38), ("right", 39)] {
                    let title = side == "left" ? "Place on Left" : "Place on Right"
                    add(title, tag)
                    menu.items.last?.representedObject = node.node.id
                    let renderedSide = goesLeft(node, among: visibleNodes()) ? "left" : "right"
                    menu.items.last?.state = renderedSide == side ? .on : .off
                }
            }
            if node.parent != nil || model.roots.count > 1 { add("Delete", 5) }
        } else {
            add("New Main Node", 3)
            add("Paste", 22)
            menu.addItem(.separator())
            add("Zoom In", 31)
            add("Zoom Out", 32)
            add("Fit Content", 33)
            menu.addItem(.separator())
            add("Select All", 34)
        }
        menu.addItem(.separator())
        add("Arrange Map", 20)
        return menu
    }
    private func relationshipMenu(for id: UUID) -> NSMenu {
        selectedRelationshipID = id
        needsDisplay = true
        let edge = model.relationships.first { $0.id == id }!
        let menu = NSMenu()
        func add(_ into: NSMenu, _ title: String, _ tag: Int, state: NSControl.StateValue = .off) {
            let item = into.addItem(withTitle: t(title), action: #selector(relationshipCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.tag = tag
            item.state = state
        }
        let styles = NSMenu()
        add(styles, "Solid", 31, state: edge.style == .solid ? .on : .off)
        add(styles, "Dashed", 32, state: edge.style == .dashed ? .on : .off)
        add(styles, "Dotted", 33, state: edge.style == .dotted ? .on : .off)
        menu.addItem(withTitle: t("Line Style"), action: nil, keyEquivalent: "").submenu = styles
        let colors = NSMenu()
        add(colors, "Default", 46, state: edge.color == nil ? .on : .off)
        for (index, swatch) in StyleInspector.colors.enumerated() {
            add(colors, swatch.0, 40 + index, state: edge.color?.uppercased() == swatch.1 ? .on : .off)
            colors.items.last?.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                StyleInspector.color(swatch.1)?.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
        }
        add(colors, "More…", 45)
        menu.addItem(withTitle: t("Color"), action: nil, keyEquivalent: "").submenu = colors
        add(menu, "Start Arrow", 34, state: edge.startArrow ? .on : .off)
        add(menu, "End Arrow", 35, state: edge.endArrow ? .on : .off)
        menu.addItem(.separator())
        add(menu, "Delete Relationship", 36)
        return menu
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let nodes = previewGeometry().nodes
        let id = nodes.last(where: { screen($0.frame).contains(point) })?.node.id
        if id == nil, let relation = relationAt(point, nodes: nodes) {
            guard commitEditing() else { return nil }
            return relationshipMenu(for: relation)
        }
        if id == nil { blankPastePoint = point }
        return contextMenu(for: id)
    }
    @objc private func relationshipCommand(_ item: NSMenuItem) {
        guard commitEditing(), let id = item.representedObject as? UUID,
              let current = model.relationships.first(where: { $0.id == id }) else { return }
        if item.tag == 36 {
            if model.removeRelationship(id) { selectedRelationshipID = nil; changed() }
            return
        }
        if item.tag == 45 {
            relationshipColorPanelID = id
            let panel = NSColorPanel.shared
            panel.color = current.color.flatMap(strokeColor) ?? .systemPurple
            panel.setTarget(self)
            panel.setAction(#selector(changeRelationshipPanelColor(_:)))
            panel.makeKeyAndOrderFront(nil)
            return
        }
        var edge = current
        switch item.tag {
        case 40...44: edge.color = StyleInspector.colors[item.tag - 40].1
        case 46: edge.color = nil
        case 31: edge.style = .solid
        case 32: edge.style = .dashed
        case 33: edge.style = .dotted
        case 34: edge.startArrow.toggle()
        case 35: edge.endArrow.toggle()
        default: return
        }
        if model.setRelationship(edge) { selectedRelationshipID = id; changed() }
    }
    @objc private func changeRelationshipPanelColor(_ panel: NSColorPanel) {
        guard commitEditing(), let id = relationshipColorPanelID, selectedRelationshipID == id,
              var edge = model.relationships.first(where: { $0.id == id }),
              let color = panel.color.usingColorSpace(.deviceRGB) else { return }
        edge.color = StyleInspector.hex(color)
        if model.setRelationship(edge) { changed() }
    }
    @objc private func contextCommand(_ item: NSMenuItem) {
        switch item.tag {
        case 0: beginEditing()
        case 37: if commitEditing(), model.selectedIDs.count == 1 { onEditNote?(model.selected) }
        case 1: addChild()
        case 2: addSibling()
        case 3: addMainNode()
        case 4: toggleFold()
        case 5: guard commitEditing() else { return }; if model.remove() { changed() }
        case 10...14:
            guard commitEditing() else { return }
            let width: CGFloat? = item.tag == 10 ? nil : MapNode.widthPresets[item.tag - 11]
            if model.setWidth(width) { changed() }
        case 16: showFontPanel()
        case 38, 39:
            guard let id = item.representedObject as? UUID,
                  model.selectedIDs.count == 1, model.selected == id,
                  commitEditing() else { return }
            let nodes = visibleNodes()
            guard let branch = nodes.first(where: { $0.node.id == id }),
                  let parent = branch.parent, nodes.first(where: { $0.node.id == parent })?.parent == nil,
                  goesLeft(branch, among: nodes) != (item.tag == 38) else { return }
            if model.setRootBranchSide(item.tag == 38 ? "left" : "right", for: id) { changed() }
        case 20: arrangeMap()
        case 21: copy(nil)
        case 22: paste(nil)
        case 30: createRelationship(nil)
        case 31, 32:
            let point = blankPastePoint ?? CGPoint(x: bounds.midX, y: bounds.midY)
            zoom(at: point, by: item.tag == 31 ? 1.25 : 0.8)
        case 33: _ = fitMapInView()
        case 34: selectAll(nil)
        case 15:
            guard commitEditing() else { return }
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

    @objc func createRelationship(_ sender: Any?) {
        guard commitEditing() else { return }
        guard model.selectedIDs.count == 2 else { return }
        let ids = visibleNodes().map(\.node.id).filter { model.selectedIDs.contains($0) }
        guard ids.count == 2 else { return }
        let edge = MapRelationship(from: ids[0], to: ids[1])
        if model.setRelationship(edge) { selectedRelationshipID = edge.id; changed() }
    }

    func showFontPanel() {
        guard commitEditing() else { return }
        guard let node = selectedNode() else { return }
        NSFontManager.shared.setSelectedFont(font(for: node.node, isRoot: node.parent == nil), isMultiple: false)
        window?.makeFirstResponder(self)
        NSFontManager.shared.orderFrontFontPanel(self)
    }
    @objc func changeFont(_ manager: NSFontManager) {
        guard commitEditing(), let node = selectedNode() else { return }
        let changedFont = manager.convert(font(for: node.node, isRoot: node.parent == nil))
        if model.setFont(family: changedFont.fontName, size: Double(changedFont.pointSize)) { changed() }
    }

    override func keyDown(with event: NSEvent) {
        if let action = NodeShortcuts.command(code: event.keyCode, modifiers: event.modifierFlags,
                                               defaults: localizationDefaults),
           performNodeShortcut(action) { return }
        if event.modifierFlags.contains(.command) {
            if event.modifierFlags.intersection([.shift, .option, .control]).isEmpty,
               event.charactersIgnoringModifiers?.lowercased() == "n" { addMainNode(); return }
            if !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control),
               [UInt16(125), 126].contains(event.keyCode) {
                guard commitEditing() else { return }
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
        case 4 where event.modifierFlags.intersection([.option, .control, .shift]).isEmpty:
            handTool = true; window?.invalidateCursorRects(for: self)
        case 9 where event.modifierFlags.intersection([.option, .control, .shift]).isEmpty:
            handTool = false; window?.invalidateCursorRects(for: self)
        case 53 where handTool:
            handTool = false; marquee = nil; dragOrigin = nil
            window?.invalidateCursorRects(for: self); needsDisplay = true
        case 53 where dragSource != nil || marquee != nil || relationshipDrag != nil || selectedRelationshipID != nil:
            stopSpring(); dragSource = nil; dragPoint = nil; dragOrigin = nil; marquee = nil
            relationshipDrag = nil; selectedRelationshipID = nil; needsDisplay = true
        case 51, 117:
            guard commitEditing() else { return }
            if let id = selectedRelationshipID {
                if model.removeRelationship(id) { selectedRelationshipID = nil; changed() }
                else { selectedRelationshipID = nil; needsDisplay = true }
            } else if model.remove() { changed() }
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
        guard commitEditing() else { return }
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
        if let target { selectedRelationshipID = nil; model.selected = target.node.id; revealSelection(); needsDisplay = true }
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
        guard commitEditing() else { return }
        let wasPresented = !springPositions.isEmpty
        let hitNodes = wasPresented ? previewGeometry().nodes : visibleNodes()
        stopSpring()
        dragSource = nil
        dragPoint = nil
        relationshipDrag = nil
        resize = nil
        marquee = nil
        if wasPresented { needsDisplay = true } // A no-hit click must not leave stale spring paint or AX.
        let point = convert(event.locationInWindow, from: nil)
        dragOrigin = point
        if handTool { window?.makeFirstResponder(self); return }
        if event.clickCount == 1,
           let node = hitNodes.last(where: { plusHit(point, item: $0, among: hitNodes) }) {
            hoveredPlus.removeAll()
            dragOrigin = nil
            model.selected = node.node.id
            addChild()
            return
        }
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command]).isEmpty,
           let id = selectedRelationshipID,
           let edge = model.relationships.first(where: { $0.id == id }),
           let curve = relationGeometry(edge, nodes: hitNodes) {
            for (first, handle) in [(true, curve.control1), (false, curve.control2)] {
                let center = screen(handle)
                if hypot(point.x - center.x, point.y - center.y) <= 11 {
                    relationshipDrag = (id, first, CGPoint(x: point.x - center.x, y: point.y - center.y), center)
                    dragOrigin = nil
                    window?.makeFirstResponder(self)
                    return
                }
            }
        }
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command]).isEmpty,
           let selected = hitNodes.first(where: { model.selectedIDs.contains($0.node.id) &&
               abs(point.x - resizeHandlePoint($0, among: hitNodes).x) <= 11 &&
               abs(point.y - resizeHandlePoint($0, among: hitNodes).y) <= 11 }) {
            let widths = Dictionary(uniqueKeysWithValues: hitNodes.filter {
                model.selectedIDs.contains($0.node.id)
            }.map { ($0.node.id, $0.frame.width) })
            resize = (selected.node.id, point.x, selected.frame.width, selected.frame.width, widths)
            needsDisplay = true
            return
        }
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command]).isEmpty,
           let mediaNode = hitNodes.last(where: { videoRect($0)?.contains(point) == true }) {
            model.selectOnly(mediaNode.node.id)
            _ = playVideo(mediaNode.node.id)
            dragOrigin = nil
            needsDisplay = true
            return
        }
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command]).isEmpty,
           !hitNodes.contains(where: { screen($0.frame).contains(point) }),
           let relation = relationAt(point, nodes: hitNodes) {
            selectedRelationshipID = relation
            dragOrigin = nil
            needsDisplay = true
            window?.makeFirstResponder(self)
            return
        }
        selectedRelationshipID = nil
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
            dragSource = event.clickCount == 1 ? node.node.id : nil
            let box = screen(node.frame)
            dragGrab = CGPoint(x: point.x - box.minX, y: point.y - box.minY)
            needsDisplay = true
            if event.clickCount == 2 { beginEditing() }
        } else {
            blankPastePoint = point
            model.selectOnly(model.selected)
            needsDisplay = true
        }
        if editor == nil { window?.makeFirstResponder(self) }
    }
    private func pan(to point: CGPoint) {
        guard let origin = dragOrigin else { return }
        offset.x += point.x - origin.x
        offset.y += point.y - origin.y
        dragOrigin = point
        editor?.frame = selectedNode().map(editorFrame) ?? .zero
        needsDisplay = true
    }
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { super.otherMouseDown(with: event); return }
        guard commitEditing() else { return }
        middlePanning = true
        dragOrigin = convert(event.locationInWindow, from: nil)
        window?.invalidateCursorRects(for: self)
    }
    override func otherMouseDragged(with event: NSEvent) {
        guard middlePanning else { super.otherMouseDragged(with: event); return }
        pan(to: convert(event.locationInWindow, from: nil))
    }
    override func otherMouseUp(with event: NSEvent) {
        guard middlePanning else { super.otherMouseUp(with: event); return }
        middlePanning = false
        dragOrigin = nil
        window?.invalidateCursorRects(for: self)
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handTool { pan(to: point); return }
        if var drag = relationshipDrag {
            drag.point = CGPoint(x: point.x - drag.grab.x, y: point.y - drag.grab.y)
            relationshipDrag = drag
            needsDisplay = true
            return
        }
        if var resize {
            let nodes = visibleNodes(for: model.roots)
            let left = nodes.first(where: { $0.node.id == resize.id }).map { goesLeft($0, among: nodes) } ?? false
            let media = model.selectedIDs.count == 1 && nodes.first(where: { $0.node.id == resize.id }).map {
                $0.node.image != nil || $0.node.video != nil
            } == true
            resize.currentWidth = min(1000, max(60, resize.startWidth + (left && !media ? -1 : 1) *
                (point.x - resize.startX) / zoom))
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
            guard marquee != nil || hypot(point.x - origin.x, point.y - origin.y) >= 9 else { return }
            marquee = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                             width: abs(point.x - origin.x), height: abs(point.y - origin.y))
            needsDisplay = true
        }
    }
    override func mouseUp(with event: NSEvent) {
        defer { stopSpring(); dragSource = nil; dragPoint = nil; dragOrigin = nil; resize = nil; marquee = nil; relationshipDrag = nil; needsDisplay = true }
        if let drag = relationshipDrag,
           let edge = model.relationships.first(where: { $0.id == drag.id }) {
            let nodes = visibleNodes()
            let nodeID = drag.first ? edge.from : edge.to
            guard let node = nodes.first(where: { $0.node.id == nodeID }),
                  let preview = relationGeometry(edge, nodes: nodes) else { return }
            var changedEdge = edge
            let anchor = drag.first ? preview.start : preview.end
            let point = world(drag.point)
            let value = SIMD2(Double(point.x - anchor.x), Double(point.y - anchor.y))
            let aim = SIMD2(Double(point.x - node.frame.midX), Double(point.y - node.frame.midY))
            if drag.first { changedEdge.control1 = value; changedEdge.control1Aim = aim }
            else { changedEdge.control2 = value; changedEdge.control2Aim = aim }
            if model.setRelationship(changedEdge) { changed() }
            return
        }
        if let marquee {
            _ = model.selectNodes(Set(visibleNodes().filter { screen($0.frame).intersects(marquee) }.map { $0.node.id }))
            return
        }
        if handTool { return }
        if let handle = resize {
            let delta = handle.currentWidth - handle.startWidth
            guard abs(delta) > 0.5 else { return }
            if model.selectedIDs.count == 1,
               let selected = selectedNode(), let image = selected.node.image {
                let width = min(1000, max(60, image.displaySize(width: selected.node.imageWidth).width + delta))
                if model.setImageWidth(width) { resize = nil; changed() }
            } else if model.selectedIDs.count == 1,
                      let selected = selectedNode(), let video = selected.node.video {
                let width = min(1000, max(60, video.displaySize(width: selected.node.videoWidth).width + delta))
                if model.setVideoWidth(width) { resize = nil; changed() }
            } else {
                let nodes = visibleNodes(for: model.roots)
                let centers = Dictionary(uniqueKeysWithValues: nodes.map {
                    ($0.node.id, CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                })
                let left = Set(nodes.filter { goesLeft($0, among: nodes) }.map { $0.node.id })
                if model.resizeSelected(by: delta, visibleWidths: handle.visibleWidths,
                                        visibleCenters: centers, renderedLeft: left) {
                    resize = nil; changed(reveal: false)
                }
            }
            return
        }
        guard let source = dragSource, dragPoint != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let nodes = visibleNodes()
        guard let anchor = nodes.first(where: { $0.node.id == source }) else { return }
        if anchor.parent == nil, let origin = dragOrigin {
            let delta = CGPoint(x: (point.x - origin.x) / zoom, y: (point.y - origin.y) / zoom)
            let centers = Dictionary(uniqueKeysWithValues: nodes.map {
                ($0.node.id, CGPoint(x: $0.frame.midX, y: $0.frame.midY))
            })
            if model.translateSelectedSubtrees(by: delta, visibleCenters: centers) { changed() }
            return
        }
        if model.selectedIDs.count == 1, let parentID = anchor.parent,
           let parent = nodes.first(where: { $0.node.id == parentID && $0.parent == nil }) {
            let rootX = screen(parent.frame).midX
            let side = point.x < rootX ? "left" : "right"
            // Only a release on the opposite side changes direction; same-side drops retain normal behavior.
            if (point.x < rootX) != goesLeft(anchor, among: nodes) {
                if model.setRootBranchSide(side, for: source) { changed() }
                return
            }
        }
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
    private var importedMindNode: MindNodeDetailedImport?
    private var savedRoots: [MapNode] = []
    private var savedRelationships: [MapRelationship] = []
    private var savedTheme: String?
    private var savedCanvasColor: String?
    private var dirty = false
    private var closeApproved = false
    private var settingsWindow: NSWindow?
    private var findWindow: NSPanel?
    private var findField: NSSearchField?
    private var findStatus: NSTextField?
    private var findMatches: [UUID] = []
    private var findIndex = 0
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
            if self?.findWindow?.isVisible == true { self?.refreshFindResults() }
        }
        canvas.onSelectionChange = { [weak self] in
            self?.outline.syncSelection(); self?.inspector.refresh()
        }
        canvas.onImageError = { [weak self] error in
            self?.alert("Could not import image", detail: error.localizedDescription)
        }
        canvas.onVideoError = { [weak self] error in
            self?.alert("Could not import video", detail: error.localizedDescription)
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "\(t("Untitled")) — \(t("OpenMindFlow"))"
        window.delegate = self
        window.minSize = NSSize(width: 640, height: 400)
        window.contentViewController = splitController
        window.toolbar = makeToolbar()
        window.setContentSize(NSSize(width: 1280, height: 700))
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
        // ponytail: compares embedded video bytes on each edit; use revision IDs if large maps stutter.
        dirty = canvas.model.roots != savedRoots || canvas.model.relationships != savedRelationships ||
            canvas.model.theme != savedTheme || canvas.model.canvasColor != savedCanvasColor
        updateTitle()
    }
    private func updateTitle() { window.title = "\(fileURL?.lastPathComponent ?? t("Untitled"))\(dirty ? " •" : "") — \(t("OpenMindFlow"))" }
    private func alert(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = t(message)
        alert.informativeText = t(detail)
        alert.alertStyle = .warning
        alert.runModal()
    }
    private func commitPendingEditors() -> Bool {
        canvas.commitEditing() && inspector.commitNoteEditing()
    }
    private func confirmDiscardOrSave() -> Bool {
        guard commitPendingEditors() else { return false }
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
        guard commitPendingEditors() else { return }
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
            _ = try readOwnDocument(url) // Reject invalid files without prompting to discard edits.
            guard confirmDiscardOrSave() else { return }
            // Saving may have changed this same path; never install the pre-save tree.
            let document = try readOwnDocument(url)
            canvas.replacingModel = true
            canvas.model = MapModel(roots: document.roots, selected: document.roots.first?.id ?? UUID(),
                                    theme: document.theme, canvasColor: document.canvasColor)
            canvas.model.relationships = document.relationships
            canvas.branchStyles = [:]
            canvas.nativePresentation = [:]
            canvas.embeddedTheme = nil
            importedMindNode = nil
            outline.reloadMap()
            inspector.refresh()
            fileURL = url
            savedRoots = document.roots
            savedRelationships = document.relationships
            savedTheme = document.theme
            savedCanvasColor = document.canvasColor
            dirty = false
            updateTitle()
            canvas.replacingModel = false
            canvas.fitMapInView()
            refreshFindResults(navigate: false)
            window.makeFirstResponder(canvas)
        } catch { alert("Could not open map", detail: error.localizedDescription) }
    }
    @objc private func openMindNode(_ sender: Any?) {
        guard commitPendingEditors() else { return }
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
            canvas.replacingModel = true
            canvas.model = MapModel(roots: imported.roots, selected: imported.roots.first?.id ?? UUID())
            canvas.branchStyles = imported.styles
            canvas.embeddedTheme = imported.theme
            canvas.nativePresentation = imported.presentation
            importedMindNode = imported
            outline.reloadMap()
            inspector.refresh()
            fileURL = nil // Never save into the source package.
            savedRoots = imported.roots
            savedRelationships = []
            savedTheme = nil
            savedCanvasColor = nil
            dirty = false
            updateTitle()
            canvas.replacingModel = false
            canvas.fitMapInView()
            refreshFindResults(navigate: false)
            window.makeFirstResponder(canvas)
            if imported.hasUnimportedConnections || imported.hasUnimportedAttachments ||
               imported.hasUnimportedRichTitles || imported.theme != nil || imported.hasUnimportedTheme {
                alert("MindNode content not imported", detail:
                    "This source has connections, attachments, rich titles or a theme that cannot be fully saved in .mindmap.json. The source remains unchanged.")
            }
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
    @objc private func insertImageFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .heif]
        #if HEADLESS_TEST
        guard let directory = ownedPanelFixtureDirectory() else { return }
        panel.directoryURL = directory
        #endif
        guard panel.runModal() == .OK, let url = panel.url else { return }
        #if HEADLESS_TEST
        guard url.deletingLastPathComponent().resolvingSymlinksInPath() == directory else { return }
        #endif
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var data = Data()
            while let chunk = try file.read(upToCount: 8 * 1024 * 1024 + 1 - data.count), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= 8 * 1024 * 1024 else { throw MapImageError.tooLarge }
            }
            try canvas.insertImageData(data)
        } catch { alert("Could not import image", detail: error.localizedDescription) }
    }
    @objc private func insertVideoFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "m4v") ?? .movie]
        #if HEADLESS_TEST
        guard let directory = ownedPanelFixtureDirectory() else { return }
        panel.directoryURL = directory
        #endif
        guard panel.runModal() == .OK, let url = panel.url else { return }
        #if HEADLESS_TEST
        guard url.deletingLastPathComponent().resolvingSymlinksInPath() == directory else { return }
        #endif
        do { try canvas.insertVideoFile(url) }
        catch { alert("Could not import video", detail: error.localizedDescription) }
    }
    @objc private func exportMindNodeCopy(_ sender: Any?) {
        guard commitPendingEditors() else { return }
        let panel = NSSavePanel()
        #if HEADLESS_TEST
        guard let directory = ownedPanelFixtureDirectory() else { return }
        panel.directoryURL = directory
        #endif
        panel.allowedContentTypes = [UTType(filenameExtension: "mindnode") ?? .data]
        panel.nameFieldStringValue = "OpenMindFlow-Copy.mindnode"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        #if HEADLESS_TEST
        guard url.deletingLastPathComponent().resolvingSymlinksInPath() == directory else { return }
        #endif
        do {
            try MindNodeWriter.write(canvas.model.roots, to: url,
                                     imported: importedMindNode,
                                     relationships: canvas.model.relationships,
                                     theme: canvas.model.theme, canvasColor: canvas.model.canvasColor)
        } catch { alert("Could not export MindNode copy", detail: error.localizedDescription) }
    }
    @objc private func exportPDF(_ sender: Any?) { export(.pdf, extension: "pdf", type: .pdf) }
    @objc private func exportPNG(_ sender: Any?) { export(.png, extension: "png", type: .png) }
    @objc private func exportJPEG(_ sender: Any?) { export(.jpeg, extension: "jpg", type: .jpeg) }
    @objc private func exportMarkdownFile(_ sender: Any?) {
        export(.markdown, extension: "md", type: UTType(filenameExtension: "md") ?? .plainText)
    }
    private func export(_ format: MapExportFormat, extension suffix: String, type: UTType) {
        guard commitPendingEditors() else { return }
        let panel = NSSavePanel()
        #if HEADLESS_TEST
        guard let directory = ownedPanelFixtureDirectory() else { return }
        panel.directoryURL = directory
        #endif
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "OpenMindFlow.\(suffix)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        #if HEADLESS_TEST
        guard url.deletingLastPathComponent().resolvingSymlinksInPath() == directory else { return }
        #endif
        do { try exportMap(canvas, as: format, to: url) }
        catch { alert("Could not export map", detail: error.localizedDescription) }
    }
    @objc private func saveFile(_ sender: Any?) { _ = save() }
    private func save() -> Bool {
        guard commitPendingEditors() else { return false }
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
            try writeOwnDocument(OwnMapDocument(roots: canvas.model.roots,
                                                relationships: canvas.model.relationships,
                                                theme: canvas.model.theme,
                                                canvasColor: canvas.model.canvasColor), to: url)
            fileURL = url
            savedRoots = canvas.model.roots
            savedRelationships = canvas.model.relationships
            savedTheme = canvas.model.theme
            savedCanvasColor = canvas.model.canvasColor
            dirty = false
            updateTitle()
            return true
        } catch {
            alert("Could not save map", detail: error.localizedDescription)
            return false
        }
    }
    @objc private func undoEdit(_ sender: Any?) { if commitPendingEditors() { canvas.undo() } }
    @objc private func redoEdit(_ sender: Any?) { if commitPendingEditors() { canvas.redo() } }
    @objc private func newChild(_ sender: Any?) { canvas.addChild() }
    @objc private func newSibling(_ sender: Any?) { canvas.addSibling() }
    @objc private func newSiblingBefore(_ sender: Any?) { canvas.addSibling(before: true) }
    @objc private func newParent(_ sender: Any?) { canvas.addParent() }
    @objc private func newMainNode(_ sender: Any?) { canvas.addMainNode() }
    @objc private func detachNode(_ sender: Any?) { canvas.detachSelected() }
    @objc private func foldNode(_ sender: Any?) { canvas.toggleFold() }
    @objc private func showNodeFont(_ sender: Any?) { canvas.showFontPanel() }
    @objc private func createNodeRelationship(_ sender: Any?) { canvas.createRelationship(sender) }
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
    @objc private func toggleStyle(_ sender: Any?) {
        guard !splitController.splitViewItems[2].isCollapsed ? commitPendingEditors() : true else { return }
        togglePane(at: 2)
    }

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
        sidebar.isCollapsed = true
        let canvasController = NSViewController()
        canvasController.view = canvas
        split.addSplitViewItem(NSSplitViewItem(viewController: canvasController))
        let inspectorController = NSViewController()
        inspector = StyleInspector(canvas: canvas, defaults: defaults)
        canvas.onEditNote = { [weak self] id in
            guard let self, self.canvas.model.selectedIDs == [id] else { return }
            if self.splitController.splitViewItems[2].isCollapsed { self.togglePane(at: 2) }
            _ = self.inspector.selectNotes(for: id)
        }
        inspectorController.view = inspector
        let style = NSSplitViewItem(viewController: inspectorController)
        style.canCollapse = true
        style.minimumThickness = 260
        style.maximumThickness = 320
        style.holdingPriority = .defaultHigh
        split.addSplitViewItem(style)
        style.isCollapsed = true
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
        if let popup = settingsWindow?.contentView?.subviews.compactMap({ $0 as? NSPopUpButton })
            .first(where: { $0.identifier?.rawValue == "general-appearance" }) {
            popup.select(popup.itemArray.first { ($0.representedObject as? String) == mode })
        }
    }

    @objc private func showFind(_ sender: Any?) {
        if findWindow == nil {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 430, height: 110),
                                styleMask: [.titled, .closable, .utilityWindow],
                                backing: .buffered, defer: false)
            panel.title = t("Find")
            let field = NSSearchField(frame: CGRect(x: 16, y: 58, width: 398, height: 28))
            field.placeholderString = t("Search nodes")
            field.setAccessibilityLabel(t("Search nodes"))
            field.sendsSearchStringImmediately = true
            field.target = self
            field.action = #selector(findChanged(_:))
            panel.contentView?.addSubview(field)
            let status = NSTextField(labelWithString: t("No matches"))
            status.frame = CGRect(x: 16, y: 16, width: 300, height: 24)
            panel.contentView?.addSubview(status)
            let next = NSButton(title: "›", target: self, action: #selector(findNext(_:)))
            next.frame = CGRect(x: 369, y: 12, width: 44, height: 28)
            next.setAccessibilityLabel(t("Next Result"))
            panel.contentView?.addSubview(next)
            findWindow = panel
            findField = field
            findStatus = status
            panel.center()
        }
        findWindow?.makeKeyAndOrderFront(nil)
        refreshFindResults()
        if let findField { findWindow?.makeFirstResponder(findField) }
    }
    @objc private func findChanged(_ sender: NSSearchField) {
        findMatches = searchTitles(canvas.model.roots, query: sender.stringValue)
        findIndex = 0
        updateFindResult()
    }
    @objc private func findNext(_ sender: Any?) {
        let current = searchTitles(canvas.model.roots, query: findField?.stringValue ?? "")
        if current != findMatches { findMatches = current; findIndex = 0 }
        else if !findMatches.isEmpty { findIndex = (findIndex + 1) % findMatches.count }
        updateFindResult()
    }
    private func refreshFindResults(navigate: Bool = true) {
        guard let findField else { return }
        let current = searchTitles(canvas.model.roots, query: findField.stringValue)
        if current != findMatches { findMatches = current; findIndex = 0 }
        updateFindResult(navigate: navigate)
    }
    private func updateFindResult(navigate: Bool = true) {
        findStatus?.stringValue = findMatches.isEmpty ? t("No matches") : "\(findIndex + 1) / \(findMatches.count)"
        if navigate && !findMatches.isEmpty { canvas.showSearchResult(findMatches[findIndex]) }
    }

    @objc private func showSettings(_ sender: Any?) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 540, height: 390),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let tabs = NSSegmentedControl(labels: [t("General"), t("Keyboard Shortcuts")],
                                      trackingMode: .selectOne, target: self, action: #selector(chooseSettingsTab(_:)))
        tabs.frame = CGRect(x: 125, y: 310, width: 290, height: 54)
        tabs.selectedSegment = 0
        tabs.setImage(NSImage(systemSymbolName: "gearshape", accessibilityDescription: t("General")), forSegment: 0)
        tabs.setImage(NSImage(systemSymbolName: "keyboard", accessibilityDescription: t("Keyboard Shortcuts")), forSegment: 1)
        tabs.setAccessibilityLabel(t("Settings Page"))
        panel.contentView?.addSubview(tabs)
        let label = NSTextField(labelWithString: t("Interface Language"))
        label.identifier = NSUserInterfaceItemIdentifier("general-Interface Language")
        label.frame = CGRect(x: 28, y: 246, width: 130, height: 22)
        let popup = NSPopUpButton(frame: CGRect(x: 164, y: 240, width: 344, height: 30), pullsDown: false)
        popup.identifier = NSUserInterfaceItemIdentifier("general-language")
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
        let appearanceLabel = NSTextField(labelWithString: t("Appearance"))
        appearanceLabel.identifier = NSUserInterfaceItemIdentifier("general-Appearance")
        appearanceLabel.frame = CGRect(x: 28, y: 188, width: 130, height: 22)
        panel.contentView?.addSubview(appearanceLabel)
        let appearancePopup = NSPopUpButton(frame: CGRect(x: 164, y: 182, width: 344, height: 30), pullsDown: false)
        appearancePopup.identifier = NSUserInterfaceItemIdentifier("general-appearance")
        for (key, name) in [("system", "System"), ("light", "Light"), ("dark", "Dark")] {
            let item = appearancePopup.menu!.addItem(withTitle: t(name), action: nil, keyEquivalent: "")
            item.representedObject = key
        }
        let mode = defaults.string(forKey: "appearance") ?? "system"
        appearancePopup.select(appearancePopup.itemArray.first { ($0.representedObject as? String) == mode }
            ?? appearancePopup.item(at: 0)!)
        appearancePopup.setAccessibilityLabel(t("Appearance"))
        appearancePopup.target = self
        appearancePopup.action = #selector(chooseSettingsAppearance(_:))
        panel.contentView?.addSubview(appearancePopup)
        let shrink = NSButton(checkboxWithTitle: t("Shrink new nodes to fit content"), target: self,
                              action: #selector(chooseShrinkNewNodes(_:)))
        shrink.identifier = NSUserInterfaceItemIdentifier("general-shrink")
        shrink.frame = CGRect(x: 164, y: 121, width: 344, height: 30)
        shrink.setAccessibilityLabel(t("Shrink new nodes to fit content"))
        shrink.state = defaults.object(forKey: "shrinkNewNodesToFitContent") == nil ||
            defaults.bool(forKey: "shrinkNewNodesToFitContent") ? .on : .off
        panel.contentView?.addSubview(shrink)
        for (index, command) in NodeShortcuts.commands.enumerated() {
            let y = CGFloat(270 - index * 39)
            let title = NSTextField(labelWithString: t(command.title))
            title.identifier = NSUserInterfaceItemIdentifier("shortcuts-label-\(command.id)")
            title.frame = CGRect(x: 28, y: y + 4, width: 188, height: 22)
            title.alignment = .right
            title.isHidden = true
            panel.contentView?.addSubview(title)
            let keys = NSPopUpButton(frame: CGRect(x: 228, y: y, width: 280, height: 30), pullsDown: false)
            keys.identifier = NSUserInterfaceItemIdentifier("shortcuts-\(command.id)")
            keys.setAccessibilityLabel(t(command.title))
            for choice in NodeShortcuts.choices {
                let item = keys.menu!.addItem(withTitle: t(choice.label), action: nil, keyEquivalent: "")
                item.representedObject = choice.key
            }
            keys.select(keys.itemArray.first {
                ($0.representedObject as? String) == NodeShortcuts.bindings(defaults)[command.id]
            }!)
            keys.target = self
            keys.action = #selector(chooseNodeShortcut(_:))
            keys.isHidden = true
            panel.contentView?.addSubview(keys)
        }
        let restore = NSButton(title: t("Restore Defaults"), target: self, action: #selector(resetNodeShortcuts(_:)))
        restore.identifier = NSUserInterfaceItemIdentifier("shortcuts-restore")
        restore.frame = CGRect(x: 228, y: 24, width: 170, height: 30)
        restore.setAccessibilityLabel(t("Restore Defaults"))
        restore.isHidden = true
        panel.contentView?.addSubview(restore)
        panel.title = t("Settings")
        panel.center()
        settingsWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func chooseSettingsTab(_ sender: NSSegmentedControl) {
        for view in settingsWindow?.contentView?.subviews ?? [] {
            guard let identifier = view.identifier?.rawValue else { continue }
            if identifier.hasPrefix("general-") { view.isHidden = sender.selectedSegment != 0 }
            if identifier.hasPrefix("shortcuts-") { view.isHidden = sender.selectedSegment != 1 }
        }
    }
    @objc private func chooseSettingsAppearance(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.representedObject as? String,
              ["system", "light", "dark"].contains(mode),
              let menu = NSApp.mainMenu?.item(withTitle: t("View"))?.submenu?
                .item(withTitle: t("Appearance"))?.submenu else { return }
        defaults.set(mode, forKey: "appearance")
        applyAppearance(mode, in: menu)
    }
    @objc private func chooseShrinkNewNodes(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: "shrinkNewNodesToFitContent")
    }
    @objc private func chooseNodeShortcut(_ sender: NSPopUpButton) {
        guard let id = sender.identifier?.rawValue.replacingOccurrences(of: "shortcuts-", with: ""),
              let key = sender.selectedItem?.representedObject as? String else { return }
        guard NodeShortcuts.set(id, key: key, defaults: defaults) else {
            let current = NodeShortcuts.bindings(defaults)[id]
            sender.select(sender.itemArray.first { ($0.representedObject as? String) == current })
            sender.toolTip = t("Shortcut already in use")
            return
        }
        sender.toolTip = nil
        installMenu()
    }
    @objc private func resetNodeShortcuts(_ sender: NSButton) {
        defaults.removeObject(forKey: "nodeShortcuts")
        for popup in settingsWindow?.contentView?.subviews.compactMap({ $0 as? NSPopUpButton }) ?? [] {
            guard let id = popup.identifier?.rawValue, id.hasPrefix("shortcuts-") else { continue }
            let key = NodeShortcuts.bindings(defaults)[String(id.dropFirst("shortcuts-".count))]
            popup.select(popup.itemArray.first { ($0.representedObject as? String) == key })
            popup.toolTip = nil
        }
        installMenu()
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
        findWindow?.title = t("Find")
        findField?.placeholderString = t("Search nodes")
        findField?.setAccessibilityLabel(t("Search nodes"))
        if findMatches.isEmpty { findStatus?.stringValue = t("No matches") }
        findWindow?.contentView?.subviews.compactMap { $0 as? NSButton }.first?.setAccessibilityLabel(t("Next Result"))
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
        for view in settingsWindow?.contentView?.subviews ?? [] {
            switch view.identifier?.rawValue {
            case "general-Appearance": (view as? NSTextField)?.stringValue = t("Appearance")
            case "general-appearance":
                if let popup = view as? NSPopUpButton {
                    popup.setAccessibilityLabel(t("Appearance"))
                    for item in popup.itemArray {
                        let title = (item.representedObject as? String ?? "system").capitalized
                        item.title = t(title)
                    }
                }
            case "general-shrink":
                (view as? NSButton)?.title = t("Shrink new nodes to fit content")
                view.setAccessibilityLabel(t("Shrink new nodes to fit content"))
            case "shortcuts-restore":
                (view as? NSButton)?.title = t("Restore Defaults")
                view.setAccessibilityLabel(t("Restore Defaults"))
            default: break
            }
            if let identifier = view.identifier?.rawValue {
                let id = identifier.replacingOccurrences(of: "shortcuts-label-", with: "")
                    .replacingOccurrences(of: "shortcuts-", with: "")
                if let command = NodeShortcuts.commands.first(where: { $0.id == id }) {
                    (view as? NSTextField)?.stringValue = t(command.title)
                    if let popup = view as? NSPopUpButton {
                        popup.setAccessibilityLabel(t(command.title))
                        for item in popup.itemArray {
                            if let choice = NodeShortcuts.choices.first(where: {
                                $0.key == item.representedObject as? String
                            }) { item.title = t(choice.label) }
                        }
                    }
                }
            }
            if let tabs = view as? NSSegmentedControl {
                tabs.setLabel(t("General"), forSegment: 0)
                tabs.setLabel(t("Keyboard Shortcuts"), forSegment: 1)
                tabs.setAccessibilityLabel(t("Settings Page"))
                tabs.setImage(NSImage(systemSymbolName: "gearshape", accessibilityDescription: t("General")), forSegment: 0)
                tabs.setImage(NSImage(systemSymbolName: "keyboard", accessibilityDescription: t("Keyboard Shortcuts")), forSegment: 1)
            }
        }
    }

    func installMenu() {
        let main = NSMenu()
        let app = NSMenuItem(title: t("OpenMindFlow"), action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: t("Settings…"), action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: t("Quit OpenMindFlow"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        main.addItem(app)
        let file = NSMenuItem(title: t("File"), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: t("File"))
        let readOnlyOpen = fileMenu.addItem(withTitle: t("Open MindNode (Read-only)…"), action: #selector(openMindNode(_:)), keyEquivalent: "o")
        readOnlyOpen.keyEquivalentModifierMask = [.command, .shift]
        readOnlyOpen.target = self
        fileMenu.addItem(withTitle: t("Open Own JSON…"), action: #selector(openFile(_:)), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: t("Save"), action: #selector(saveFile(_:)), keyEquivalent: "s").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: t("Insert Image…"), action: #selector(insertImageFile(_:)), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: t("Insert Video…"), action: #selector(insertVideoFile(_:)), keyEquivalent: "").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: t("Experimental MindNode v9 Plain-Tree Copy…"),
                         action: #selector(exportMindNodeCopy(_:)), keyEquivalent: "").target = self
        fileMenu.addItem(.separator())
        for (title, selector) in [("Export PDF…", #selector(exportPDF(_:))),
                                  ("Export PNG…", #selector(exportPNG(_:))),
                                  ("Export JPG…", #selector(exportJPEG(_:))),
                                  ("Export Markdown…", #selector(exportMarkdownFile(_:)))] {
            fileMenu.addItem(withTitle: t(title), action: selector, keyEquivalent: "").target = self
        }
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
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: t("Find…"), action: #selector(showFind(_:)), keyEquivalent: "f").target = self
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
            let command = NodeShortcuts.commands.first { $0.title == title }
            let choice = command.flatMap { node in
                NodeShortcuts.choices.first { $0.key == NodeShortcuts.bindings(defaults)[node.id] }
            }
            let useCustom = command != nil && title != "New Main Node" &&
                !(title == "New Sibling" && choice?.key == "return")
            let equivalent = useCustom ? (choice?.code == 48 ? "\t" : "\r") : key
            let item = nodeMenu.addItem(withTitle: t(title), action: action, keyEquivalent: equivalent)
            item.keyEquivalentModifierMask = useCustom ? (choice?.modifiers ?? modifiers) : modifiers
            item.target = self
        }
        nodeMenu.addItem(withTitle: t("Font…"), action: #selector(showNodeFont(_:)), keyEquivalent: "t").target = self
        nodeMenu.addItem(withTitle: t("Create Relationship"), action: #selector(createNodeRelationship(_:)), keyEquivalent: "").target = self
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
