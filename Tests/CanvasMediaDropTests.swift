import AppKit
import Darwin

@main
enum CanvasMediaDropTests {
    static func main() throws {
        _ = NSApplication.shared // Never show or activate a user window.
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let folder = base.appendingPathComponent("openmindflow-drop-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard folder.deletingLastPathComponent() == base,
              folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
              lstat(folder.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Unsafe synthetic media test directory") }
        defer {
            var current = stat()
            if folder.deletingLastPathComponent() == base,
               folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
               lstat(folder.path, &current) == 0, current.st_uid == getuid(),
               current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) { try? FileManager.default.removeItem(at: folder) }
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 16,
                                      bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<16 { for x in 0..<24 { bitmap.setColor(NSColor(deviceRed: 1, green: 0.45, blue: 0.15, alpha: 1), atX: x, y: y) } }
        let png = bitmap.representation(using: .png, properties: [:])!
        let imageURL = folder.appendingPathComponent("photo.png")
        try png.write(to: imageURL, options: .atomic)
        let selected = MapNode(id: UUID(), title: "Unchanged", children: [], folded: false,
                               location: SIMD2(130, 220))
        let canvas = MapCanvas(model: MapModel(roots: [selected], selected: selected.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 720)
        var changes = 0
        canvas.onChange = { changes += 1 }
        let board = NSPasteboard(name: .init("openmindflow-file-drop-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        assert(board.setString(imageURL.absoluteString, forType: .fileURL))
        assert(canvas.registeredDraggedTypes.contains(.fileURL), "Canvas must advertise Finder file drop support")
        assert(canvas.acceptDroppedMedia(from: board, at: CGPoint(x: 900, y: 590)),
               "Validated Finder image drop on blank canvas must be accepted")
        assert(canvas.model.roots.count == 2 && canvas.model.roots[0] == selected &&
               canvas.model.roots[1].image?.data == png &&
               canvas.model.roots[1].location == SIMD2(820, 500) && changes == 1,
               "Dropped image bytes must create one independent world-anchored root")
        canvas.undo()
        assert(canvas.model.roots == [selected], "One Undo removes dropped root without changing existing map")
        let invalidURL = folder.appendingPathComponent("not-an-image.png")
        try Data("this is not PNG".utf8).write(to: invalidURL, options: .atomic)
        board.clearContents()
        assert(board.setString(invalidURL.absoluteString, forType: .fileURL))
        let before = canvas.model.roots, beforeSelection = canvas.model.selectedIDs, beforeChanges = changes
        assert(!canvas.acceptDroppedMedia(from: board, at: CGPoint(x: 920, y: 610)),
               "Filename extension alone cannot make damaged image data importable")
        assert(canvas.model.roots == before && canvas.model.selectedIDs == beforeSelection &&
               changes == beforeChanges, "Rejected external file cannot mutate map or selection")
        let pastedImage = NSPasteboard(name: .init("openmindflow-file-paste-\(UUID().uuidString)"))
        defer { pastedImage.releaseGlobally() }
        pastedImage.clearContents()
        assert(pastedImage.setString(imageURL.absoluteString, forType: .fileURL))
        canvas.model.clearSelection()
        canvas.paste(from: pastedImage)
        assert(canvas.model.roots.count == 2 && canvas.model.roots[1].image?.data == png,
               "Pasting an image file URL should no longer route it through video-only parsing")
        var saturated = selected
        saturated.note = String(repeating: "x", count: MapModel.maxSavedJSONBytes)
        let other = MapNode(id: UUID(), title: "Keep primary", children: [], folded: false,
                            location: SIMD2(370, 360))
        let failureModel = MapModel(roots: [saturated, other], selected: saturated.id)
        failureModel.toggleSelection(other.id)
        assert(failureModel.selected == other.id && failureModel.selectedIDs == [saturated.id, other.id])
        let failureCanvas = MapCanvas(model: failureModel)
        failureCanvas.frame = canvas.frame
        board.clearContents()
        assert(board.setString(imageURL.absoluteString, forType: .fileURL))
        let target = failureCanvas.frameForAccessibility(saturated.id)!
        assert(!failureCanvas.acceptDroppedMedia(from: board,
                at: CGPoint(x: target.midX, y: target.midY)),
               "A document beyond its 32 MiB saved budget must reject an otherwise valid image")
        assert(failureModel.roots.count == 2 && failureModel.roots[0].children.isEmpty &&
               failureModel.selectedIDs == [saturated.id, other.id] && failureModel.selected == other.id,
               "Rejected drop must preserve both multi-selection set and former primary")
        print("Finder image drop/paste, world anchor, invalid and capacity rejections passed")
    }
}
