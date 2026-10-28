import AppKit

@main enum SettingsVisualLayoutTests {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for language in ["en", "zh-Hans"] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suite = "local.openmindflow.settings-layout.\(UUID())"
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                assert(L10n.setLanguage(language, defaults: defaults))
                let delegate = AppDelegate(defaults: defaults)
                var callback: ((Data?, URLResponse?, Error?) -> Void)?
                delegate.releaseChecker = ReleaseChecker(fetch: { _, completion in callback = completion })
                delegate.installMenu()
                let settings = NSApp.mainMenu!.items[0].submenu!.item(withTitle: L10n.text("Settings…", defaults: defaults))!
                assert(NSApp.sendAction(settings.action!, to: settings.target, from: settings))
                let panel = NSApp.windows.last { $0.title == L10n.text("Settings", defaults: defaults) }!
                panel.appearance = NSAppearance(named: appearance)
                let content = panel.contentView!
                assert(content.frame.width >= 620 && content.frame.height >= 470, "Compact three-page settings needs 620×470 content")
                let tabs = content.subviews.compactMap { $0 as? NSSegmentedControl }.first!
                assert(tabs.frame.height <= 32 && tabs.segmentCount == 3, "Compact page navigation")
                func descendants(_ view: NSView) -> [NSView] {
                    view.subviews.flatMap { [$0] + descendants($0) }
                }
                func item(_ id: String) -> NSView {
                    guard let found = descendants(content).first(where: { $0.identifier?.rawValue == id }) else {
                        fatalError("Missing \(id)")
                    }
                    return found
                }
                let pages = ["general", "shortcuts", "about"].map { item("\($0)-page") }
                assert(Set(pages.map { ObjectIdentifier($0) }).count == 3 &&
                       pages.allSatisfy { $0.superview === content }, "Each page needs a separate native container")
                for page in ["general", "shortcuts", "about"] {
                    assert(item("\(page)-page-title").superview === item("\(page)-page"),
                           "Page controls must belong to their own container")
                }
                for (index, page) in ["general", "shortcuts", "about"].enumerated() {
                    tabs.selectedSegment = index
                    assert(NSApp.sendAction(tabs.action!, to: tabs.target, from: tabs))
                    let heading = item("\(page)-page-title") as! NSTextField
                    assert(!heading.isHidden && !heading.stringValue.isEmpty)
                    let container = item("\(page)-page")
                    assert(!container.isHidden && pages.enumerated().allSatisfy { $0.offset == index || $0.element.isHidden },
                           "Only the selected page container should be visible")
                    for view in descendants(container) where !view.isHidden {
                        assert(container.bounds.contains(view.frame), "\(page): \(view.identifier?.rawValue ?? "unknown") clipped")
                    }
                    let first = panel.firstResponder
                    assert(first == nil || first === panel || !pages.enumerated().contains(where: {
                        $0.offset != index && first === $0.element
                    }), "Hidden page cannot retain first responder")
                }
                tabs.selectedSegment = 0
                assert(NSApp.sendAction(tabs.action!, to: tabs.target, from: tabs))
                let languageLabel = item("general-Interface Language")
                let languagePopup = item("general-language")
                assert(languageLabel.frame.maxX + 8 <= languagePopup.frame.minX)
                assert((languageLabel as! NSTextField).intrinsicContentSize.width <= languageLabel.frame.width)
                assert(panel.makeFirstResponder(languagePopup))
                tabs.selectedSegment = 1
                assert(NSApp.sendAction(tabs.action!, to: tabs.target, from: tabs))
                assert(panel.firstResponder === item("shortcuts-new-child"),
                       "Switching tabs must focus the first control of the newly visible page")
                let rows = ["new-child", "new-sibling", "new-sibling-before", "new-main", "new-parent", "edit-title"].map { id -> (NSView, NSView) in
                    (item("shortcuts-label-\(id)"), item("shortcuts-\(id)"))
                }
                for (label, control) in rows {
                    assert(label.frame.maxX + 8 <= control.frame.minX)
                    assert((label as! NSTextField).intrinsicContentSize.width <= label.frame.width)
                }
                for first in 0..<rows.count {
                    for second in (first + 1)..<rows.count {
                        assert(!rows[first].0.frame.intersects(rows[second].0.frame), "Shortcut rows overlap")
                    }
                }
                let restore = item("shortcuts-restore")
                assert(rows.allSatisfy { $0.0.frame.minY > restore.frame.maxY })
                tabs.selectedSegment = 2
                assert(NSApp.sendAction(tabs.action!, to: tabs.target, from: tabs))
                let version = item("about-version") as! NSTextField
                assert(version.stringValue.contains("Version") || version.stringValue.contains("版本"))
                assert(!(item("about-credits") as! NSTextField).stringValue.isEmpty)
                let disclosure = item("about-statement") as! NSTextField
                assert(disclosure.stringValue.contains("IdeasOnCanvas"))
                let channel = item("about-channel") as! NSPopUpButton
                assert(channel.selectedItem?.representedObject as? String == "stable", "Selected channel: \(String(describing: channel.selectedItem?.representedObject)); titles \(channel.itemTitles)")
                assert(item("about-channel-caution").isHidden,
                       "Stable channel must not show Beta-specific caution")
                assert(defaults.object(forKey: "updateChannel") == nil)
                assert((item("about-auto-updates") as! NSButton).state == .off)
                channel.select(channel.itemArray.first { $0.representedObject as? String == "beta" })
                assert(NSApp.sendAction(channel.action!, to: channel.target, from: channel))
                assert(defaults.string(forKey: "updateChannel") == "beta")
                assert(!item("about-channel-caution").isHidden &&
                       (item("about-channel-caution") as! NSTextField).stringValue.count > 8)
                let status = item("about-status") as! NSTextField
                assert(status.frame.height >= 42 && status.cell?.wraps == true,
                       "Long validated version status needs a wrapping multi-line region")
                let check = item("about-check-now") as! NSButton
                assert(NSApp.sendAction(check.action!, to: check.target, from: check))
                let longVersion = "999999999.999999999.999999999-beta.999999999"
                let payload = "[{\"tag_name\":\"v\(longVersion)\",\"html_url\":\"\(ReleaseChecker.releasesPage.absoluteString)/tag/v\(longVersion)\",\"draft\":false,\"prerelease\":true}]"
                callback!(Data(payload.utf8), HTTPURLResponse(url: ReleaseChecker.endpoint,
                    statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil), nil)
                assert(status.stringValue.contains(longVersion), "Render the actual long validated version in \(language)")
                let measured = status.attributedStringValue.boundingRect(
                    with: CGSize(width: status.frame.width, height: 1000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]).height
                assert(measured > 22 && measured <= status.frame.height,
                       "\(language) long status must wrap and fit: measured \(measured), frame \(status.frame.height)")
                // Render the actual offscreen native window, without activation, Accessibility or HID.
                panel.displayIfNeeded()
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: Int(content.bounds.width * 2), pixelsHigh: Int(content.bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                bitmap.size = content.bounds.size
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                panel.effectiveAppearance.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.withAlphaComponent(1).setFill()
                    content.bounds.fill()
                    content.displayIgnoringOpacity(content.bounds, in: context)
                }
                context.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()
                assert(bitmap.pixelsWide >= 620 && bitmap.pixelsHigh >= 470)
                var renderedColors = Set<String>()
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 5) {
                    for x in stride(from: 0, to: bitmap.pixelsWide, by: 5) {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                              color.alphaComponent > 0,
                              max(color.redComponent, color.greenComponent, color.blueComponent) > 0 else { continue }
                        renderedColors.insert("\(Int(color.redComponent * 255)),\(Int(color.greenComponent * 255)),\(Int(color.blueComponent * 255))")
                    }
                }
                assert(renderedColors.count > 1,
                       "Offscreen settings bitmap must contain multiple distinct nonblack rendered pixels: \(language), \(appearance.rawValue), \(renderedColors.count) colors")
                panel.orderOut(nil)
            }
        }
        print("native three-page Aqua/Dark English/Chinese layout and offscreen bitmaps passed")
    }
}
