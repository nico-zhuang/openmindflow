import AppKit

@main enum TabStripSurfaceTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let suite = "local.openmindflow.tabstrip.surface.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = AppDelegate(defaults: defaults)
        let owner = app.makeUnshownWindowSession()
        owner.tabStrip.onNewTab()
        let strip = owner.tabStrip
        assert(owner.window.contentView != nil && strip.window === owner.window && !owner.window.isVisible,
               "fixture must be a real, never-ordered NSWindow hierarchy")

        for orientation: DocumentTabOrientation in [.horizontal, .vertical] {
            owner.setOrientation(orientation)
            for name: NSAppearance.Name in [.aqua, .darkAqua] {
                owner.window.appearance = NSAppearance(named: name)!
                owner.window.contentView!.layoutSubtreeIfNeeded()
                strip.layoutSubtreeIfNeeded()
                let rows = strip.subviews.filter { $0.subviews.first is NSButton }
                assert(rows.count == 2 && rows.filter { ($0.subviews[0] as! NSButton).state == .on }.count == 1,
                       "\(orientation): two real tab rows with exactly one selected title")
                let selected = rows.first { ($0.subviews[0] as! NSButton).state == .on }!
                let unselected = rows.first { $0 !== selected }!
                assert(!selected.subviews[0].isHidden &&
                       (selected.subviews[0] as! NSButton).title == owner.active!.displayTabTitle(defaults: defaults),
                       "\(orientation): the selected title must belong to the active session")

                // cacheDisplay traverses the actual, flipped strip -> row -> native button hierarchy
                // in the unshown NSWindow, rather than manually invoking any draw(_:) method.
                for requestedScale in [0, 1] { // native window backing and explicit 1x offscreen bitmap
                let bitmap = requestedScale == 0 ? strip.bitmapImageRepForCachingDisplay(in: strip.bounds)! :
                    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(strip.bounds.width),
                        pixelsHigh: Int(strip.bounds.height), bitsPerSample: 8, samplesPerPixel: 4,
                        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                        bytesPerRow: 0, bitsPerPixel: 0)!
                strip.cacheDisplay(in: strip.bounds, to: bitmap)
                let scaleX = CGFloat(bitmap.pixelsWide) / strip.bounds.width
                let scaleY = CGFloat(bitmap.pixelsHigh) / strip.bounds.height
                func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor {
                    let column = min(bitmap.pixelsWide - 1, max(0, Int(x * scaleX)))
                    let line = min(bitmap.pixelsHigh - 1, max(0, Int(y * scaleY)))
                    return bitmap.colorAt(x: column, y: line)!.usingColorSpace(.deviceRGB)!
                }
                func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
                    abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) +
                        abs(a.blueComponent - b.blueComponent)
                }
                let selectedPoint = CGPoint(x: selected.frame.minX + 10, y: selected.frame.minY + 9)
                let unselectedPoint = CGPoint(x: unselected.frame.minX + 10, y: unselected.frame.minY + 9)
                let selectedInterior = pixel(selectedPoint.x, selectedPoint.y)
                let unselectedInterior = pixel(unselectedPoint.x, unselectedPoint.y)
                assert(selectedInterior.alphaComponent > 0.99 && unselectedInterior.alphaComponent > 0.99,
                       "\(orientation) \(name.rawValue): composited rows must remain opaque")
                assert(distance(selectedInterior, unselectedInterior) > 0.07,
                       "\(orientation) \(name.rawValue): selected highlight must differ from unselected strip")

                // Sample the title's glyph-bearing rectangle, excluding the row border and close button.
                // Comparison is against each row's own nearby plain background, in either appearance.
                for row in [selected, unselected] {
                    let origin = row.frame.origin
                    let background = pixel(origin.x + 10, origin.y + 9)
                    let glyphPixels = (8..<25).reduce(0) { total, y in
                        total + (17..<105).filter { x in
                            distance(pixel(origin.x + CGFloat(x), origin.y + CGFloat(y)), background) > 0.19
                        }.count
                    }
                    assert(glyphPixels > 12,
                           "\(orientation) \(name.rawValue): \(row === selected ? "selected" : "unselected") title glyphs must render legibly (\(glyphPixels) pixels)")
                }

                // Coordinates here are bitmap top-to-bottom: the NSView itself is flipped.
                // Measure both the actual canvas-facing edge and its immediately adjacent interior.
                let edge = orientation == .horizontal
                    ? pixel(400, strip.bounds.height - 0.5) : pixel(strip.bounds.width - 0.5, 160)
                let inside = orientation == .horizontal
                    ? pixel(400, strip.bounds.height - 1.5) : pixel(strip.bounds.width - 1.5, 160)
                let farSide = orientation == .horizontal
                    ? pixel(400, 0.5) : pixel(0.5, 160)
                assert(edge.alphaComponent > 0.99 && distance(edge, inside) > 0.08,
                       "\(orientation) \(name.rawValue): canvas-side separator must occupy outermost pixel")
                assert(distance(inside, farSide) < 0.02,
                       "\(orientation) \(name.rawValue): separator is one pixel, not a reversed or broad border")
                if requestedScale == 0,
                   let directory = ProcessInfo.processInfo.environment["OMF_TABSTRIP_RENDER_DIR"],
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    let file = URL(fileURLWithPath: directory)
                        .appendingPathComponent("hierarchy-\(orientation.rawValue)-\(name.rawValue).png")
                    try! png.write(to: file)
                    print("rendered \(file.path)")
                }
                }
            }
        }
        assert(!owner.window.isVisible && NSApp.activationPolicy() == .prohibited,
               "rendering must never order or activate the synthetic window")
        print("unshown NSWindow hierarchy: Aqua/Dark, both orientations, selected/unselected glyphs and canvas edges passed")
    }
}
