import AppKit

@main enum InspectorTopAlignmentTests {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited) // Never order or activate a desktop window.
        let suite = "local.mindmap.inspector-top.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
        let node = MapNode(id: UUID(), title: "Synthetic", children: [], folded: false)
        let canvas = MapCanvas(model: MapModel(roots: [node], selected: node.id))
        var failures: [String] = []
        for width in [CGFloat(260), 320] {
            let inspector = StyleInspector(canvas: canvas, defaults: defaults)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 600),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            inspector.translatesAutoresizingMaskIntoConstraints = true
            inspector.autoresizingMask = [.width, .height]
            window.contentView = inspector // Never order, focus, or activate the window.
            window.setContentSize(NSSize(width: width, height: 600))
            inspector.frame = CGRect(x: 0, y: 0, width: width, height: 600)
            let inspectorWidth = inspector.widthAnchor.constraint(equalToConstant: width)
            inspectorWidth.isActive = true
            inspector.layoutSubtreeIfNeeded()
            inspector.styleScroll.layoutSubtreeIfNeeded()
            let tabs = inspector.tabs
            let scroll = inspector.styleScroll
            let document = scroll.documentView!
            let stack = document.subviews.compactMap { $0 as? NSStackView }.first!
            let firstSection = stack.arrangedSubviews.compactMap { $0 as? NSTextField }.first!
            let headingInDocument = firstSection.convert(firstSection.bounds, to: document)
            let headingInInspector = firstSection.convert(firstSection.bounds, to: inspector)
            let visible = scroll.contentView.documentVisibleRect
            let topInset = inspector.bounds.maxY - tabs.frame.maxY
            let tabToPage = tabs.frame.minY - scroll.frame.maxY
            let documentGap = document.isFlipped ? headingInDocument.minY :
                document.bounds.maxY - headingInDocument.maxY
            let visibleGap = scroll.frame.maxY - headingInInspector.maxY
            let headingVisible = visible.intersects(headingInDocument)
            print("inspector requested=\(width) actual=\(inspector.bounds) tabs=\(tabs.frame) " +
                  "scroll=\(scroll.frame) topInset=\(topInset) tabToPage=\(tabToPage) " +
                  "documentHeadingGap=\(documentGap) actualVisibleGap=\(visibleGap) " +
                  "headingVisible=\(headingVisible) document=\(document.bounds) " +
                  "visible=\(visible) heading=\(headingInDocument)")
            if !(abs(inspector.bounds.width - width) < 0.5 &&
                 abs(scroll.frame.width - width) < 0.5 && topInset >= 0 && topInset <= 12 &&
                 tabToPage >= 0 && tabToPage <= 12 && documentGap >= 0 && documentGap <= 20 &&
                 visibleGap >= 0 && visibleGap <= 24 && headingVisible) {
                failures.append("width \(width): content does not begin near inspector top")
            }
            for (index, title) in ["Style", "Notes", "Themes"].enumerated() {
                if tabs.label(forSegment: index) != title ||
                    tabs.image(forSegment: index) != nil || tabs.toolTip(forSegment: index) != title {
                    failures.append("width \(width): Style/Notes/Themes must be text-only accessible tabs")
                }
            }
            defaults.setVolatileDomain(["language": "zh-Hans"], forName: UserDefaults.argumentDomain)
            inspector.localize()
            for (index, title) in ["样式", "注释", "主题"].enumerated() {
                if tabs.label(forSegment: index) != title ||
                    tabs.image(forSegment: index) != nil || tabs.toolTip(forSegment: index) != title {
                    failures.append("width \(width): Chinese tabs must remain localized text only")
                }
            }
            defaults.setVolatileDomain(["language": "en"], forName: UserDefaults.argumentDomain)
            window.setContentSize(NSSize(width: width, height: 250))
            inspector.frame.size.height = 250
            inspector.layoutSubtreeIfNeeded()
            scroll.layoutSubtreeIfNeeded()
            let clip = scroll.contentView
            let shortVisible = clip.documentVisibleRect
            let firstInDocument = firstSection.convert(firstSection.bounds, to: document)
            if !(abs(inspector.bounds.height - 250) < 0.5 &&
                 document.bounds.height > clip.bounds.height &&
                 scroll.hasVerticalScroller && shortVisible.intersects(firstInDocument)) {
                failures.append("width \(width): short inspector must start at the first section with working scroll")
            }
            clip.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.maxY - clip.bounds.height)))
            scroll.reflectScrolledClipView(clip)
            if clip.documentVisibleRect.maxY < document.bounds.maxY - 1 {
                failures.append("width \(width): scroll must still reach the last Style settings")
            }
            window.orderOut(nil)
        }
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        if !failures.isEmpty {
            fputs("RED \(failures.joined(separator: "; "))\n", stderr)
            exit(1)
        }
        print("inspector top geometry and text-only localized tabs passed without visible windows")
    }
}
