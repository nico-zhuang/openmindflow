import AppKit
import Darwin

@main enum NoteIndicatorTests {
    static func main() throws {
        _ = NSApplication.shared // Detached bitmap rendering; never create or focus a window.
        var noted = MapNode(id: UUID(), title: "Noted child", children: [], folded: false)
        noted.note = "Private note: never expose this text"
        var empty = MapNode(id: UUID(), title: "Empty child", children: [], folded: false)
        empty.note = " \n\t "
        var root = MapNode(id: UUID(), title: "Root", children: [noted, empty], folded: false)
        root.width = 220
        let model = MapModel(roots: [root], selected: root.id)
        let canvas = MapCanvas(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let defaults = UserDefaults(suiteName: "NoteIndicatorTests.\(UUID().uuidString)")!
        defaults.set("en", forKey: "language")
        canvas.localizationDefaults = defaults

        func bitmap(_ target: MapCanvas? = nil) -> NSBitmapImageRep {
            let target = target ?? canvas
            target.needsDisplay = true // The real note editor invalidates the canvas after MapModel.setNote.
            let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 700,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: result)
            target.effectiveAppearance.performAsCurrentDrawingAppearance { target.draw(target.bounds) }
            NSGraphicsContext.current = previous
            return result
        }
        func differs(_ before: NSBitmapImageRep, _ after: NSBitmapImageRep, in region: CGRect) -> Bool {
            for x in Int(region.minX)...Int(region.maxX) {
                for y in Int(region.minY)...Int(region.maxY) {
                    guard x >= 0, x < before.pixelsWide, y >= 0, y < before.pixelsHigh else { continue }
                    let first = before.colorAt(x: x, y: before.pixelsHigh - 1 - y)!.usingColorSpace(.deviceRGB)!
                    let second = after.colorAt(x: x, y: after.pixelsHigh - 1 - y)!.usingColorSpace(.deviceRGB)!
                    if abs(first.redComponent - second.redComponent) +
                       abs(first.greenComponent - second.greenComponent) +
                       abs(first.blueComponent - second.blueComponent) > 0.2 { return true }
                }
            }
            return false
        }
        func childRegion(_ id: UUID) -> CGRect {
            let box = canvas.frameForAccessibility(id)!
            return CGRect(x: box.maxX + 3, y: box.maxY - 34, width: 27, height: 28)
        }
        func rootRegion() -> CGRect {
            let box = canvas.frameForAccessibility(root.id)!
            return CGRect(x: box.maxX - 29, y: box.midY - 10, width: 24, height: 20)
        }
        func labels() -> [String] {
            canvas.accessibilityChildren()!.compactMap { ($0 as? NSAccessibilityElement)?.accessibilityLabel() }
        }
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            canvas.appearance = NSAppearance(named: appearance)
            assert(model.setNote("", for: noted.id))
            let noNote = bitmap()
            assert(model.setNote("Private note: never expose this text", for: noted.id))
            let withNote = bitmap()
            guard differs(noNote, withNote, in: childRegion(noted.id)) else {
                fputs("RED: nonblank child note must paint paper icon beyond its underline in \(appearance.rawValue)\n", stderr)
                exit(1)
            }
            assert(!differs(noNote, withNote, in: childRegion(empty.id)),
                   "Whitespace-only sibling cannot acquire an icon")
            assert(labels().contains("Noted child, Has note") && labels().contains("Empty child") &&
                   !labels().joined().contains("Private note"), "AX reports note presence without its contents")
        }
        defaults.set("zh-Hans", forKey: "language")
        assert(labels().contains("Noted child, 有注释"), "Note status must be localized in AX")
        defaults.set("en", forKey: "language")

        let painted = bitmap()
        assert(model.setNote("", for: noted.id))
        assert(differs(painted, bitmap(), in: childRegion(noted.id)), "Removing note removes icon immediately")
        assert(model.undo() && differs(bitmap(), painted, in: childRegion(noted.id)) == false,
               "Undo restores note icon")
        assert(model.redo() && differs(painted, bitmap(), in: childRegion(noted.id)),
               "Redo removes note icon")
        assert(model.setNote("Root details", for: root.id))
        let rootPainted = bitmap()
        assert(model.setNote("", for: root.id))
        assert(differs(rootPainted, bitmap(), in: rootRegion()), "Root icon must stay inside its content edge")

        // Editing a narrow root may extend left, but must never cover its paper icon on the right.
        var narrowRoot = MapNode(id: UUID(), title: "Narrow", children: [], folded: false)
        narrowRoot.width = 60
        narrowRoot.note = "Keep visible while editing"
        let narrowModel = MapModel(roots: [narrowRoot], selected: narrowRoot.id)
        let narrowCanvas = MapCanvas(model: narrowModel)
        narrowCanvas.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let editKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: "a", charactersIgnoringModifiers: "a", isARepeat: false,
                                     keyCode: 0)!
        narrowCanvas.keyDown(with: editKey)
        guard let titleEditor = narrowCanvas.subviews.compactMap({ $0 as? NSTextField }).first,
              let narrowBox = narrowCanvas.frameForAccessibility(narrowRoot.id) else {
            fputs("RED: narrow noted root must open a title editor\n", stderr)
            exit(1)
        }
        // Paper begins at box.maxX-22*zoom; its stroke extends slightly to the left.
        let renderedZoom = narrowBox.width / 60
        let paperLeft = narrowBox.maxX - 23.25 * renderedZoom
        guard titleEditor.frame.maxX <= paperLeft else {
            fputs("RED: narrow noted root editor overlaps paper icon (editor maxX \(titleEditor.frame.maxX), icon minX \(paperLeft))\n", stderr)
            exit(1)
        }
        assert(titleEditor.frame.width >= 48 && titleEditor.frame.minX < narrowBox.minX,
               "Narrow root editor keeps 48pt usability by extending left of the root")
        let editingPaint = bitmap(narrowCanvas)
        assert(narrowModel.setNote("", for: narrowRoot.id))
        assert(differs(editingPaint, bitmap(narrowCanvas), in: CGRect(x: narrowBox.maxX - 29,
            y: narrowBox.midY - 10, width: 24, height: 20)), "Root icon remains visible during title editing")

        let temp = FileManager.default.temporaryDirectory.standardizedFileURL
        let scratch = temp.appendingPathComponent("note-indicator-\(UUID().uuidString).mindmap.json")
        let saved = temp.appendingPathComponent("note-indicator-\(UUID().uuidString).mindmap.json")
        defer {
            for file in [scratch, saved] {
                // Delete only the two exact test-owned regular files beneath our resolved temporary directory.
                let resolved = file.resolvingSymlinksInPath().standardizedFileURL
                guard resolved == file.standardizedFileURL,
                      resolved.deletingLastPathComponent() == temp,
                      resolved.lastPathComponent.hasPrefix("note-indicator-"),
                      resolved.pathExtension == "json" else { continue }
                try? FileManager.default.removeItem(at: resolved)
            }
        }
        try writeOwnJSON(model.roots, to: scratch)
        let reopened = try readOwnJSON(scratch)
        assert(reopened[0].children[0].note == nil && reopened[0].children[1].note == " \n\t ")
        assert(model.setNote("Saved note", for: noted.id))
        // A separate path ensures the first JSON is never overwritten.
        try writeOwnJSON(model.roots, to: saved)
        let reopenedModel = MapModel(roots: try readOwnJSON(saved), selected: root.id)
        let reopenedCanvas = MapCanvas(model: reopenedModel)
        reopenedCanvas.frame = canvas.frame
        reopenedCanvas.appearance = canvas.appearance
        assert(reopenedModel.roots[0].children[0].note == "Saved note")
        assert(differs(rootPainted, bitmap(reopenedCanvas), in: childRegion(noted.id)),
               "Reopened note paints from persisted model data without separate icon state")
        print("note icon child/root light/dark, whitespace, accessibility, undo/redo and JSON reopen passed")
    }
}
