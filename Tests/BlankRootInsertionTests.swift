import AppKit
import AVFoundation
import Darwin

@main enum BlankRootInsertionTests {
    static func main() async throws {
        let a = MapNode(id: UUID(), title: "A", children: [
            MapNode(id: UUID(), title: "Child", children: [], folded: false)
        ], folded: false)
        let b = MapNode(id: UUID(), title: "B", children: [], folded: false)
        let model = MapModel(roots: [a, b], selected: a.children[0].id)
        let original = model.roots
        let image = try tinyImage()
        let video = try await tinyVideo()
        assert(model.clearSelection() && model.selectedIDs.isEmpty && model.selected == a.children[0].id)
        assert(!model.clearSelection(), "Repeated blank click cannot change undo or document")
        model.addChild(); model.addSibling(); model.addParent()
        assert(!model.addImageChild(image))
        assert(!model.addVideoChild(video))
        assert(!model.moveSibling(by: 1) && !model.detachSelected() && !model.rename("not the child") &&
               !model.remove() && !model.toggleFold() && !model.selectRange(to: b.id))
        assert(model.roots == original && !model.undo(), "No selected node means stale primary is inert")
        let center = CGPoint(x: -625.25, y: 379.5)
        assert(model.insertRoot(title: "独立主节点", at: center))
        let inserted = model.roots.last!
        assert(model.roots.count == 3 && model.roots[0] == a && model.roots[1] == b &&
               inserted.id != a.id && inserted.id != b.id && inserted.title == "独立主节点" &&
               inserted.children.isEmpty && inserted.location == SIMD2(-625.25, 379.5) &&
               model.selected == inserted.id && model.selectedIDs == [inserted.id])
        assert(model.undo() && model.roots == original && model.selectedIDs.isEmpty,
               "One undo restores prior blank selection and every root")
        assert(!model.undo(), "clearSelection must not create an undo snapshot")
        assert(model.redo() && model.roots.last?.id == inserted.id && model.selectedIDs == [inserted.id])
        let imageBefore = model.roots
        assert(model.clearSelection() && model.insertRoot(title: "Photo", image: image,
                                                 at: CGPoint(x: 200, y: 300)))
        assert(model.roots.last?.image == image && model.roots.last?.video == nil &&
               model.roots.last?.location == SIMD2(200, 300))
        assert(model.undo() && model.roots == imageBefore && model.selectedIDs.isEmpty)
        assert(model.insertRoot(title: "Clip", video: video, at: CGPoint(x: 340, y: 160)))
        assert(model.roots.last?.video == video && model.roots.last?.image == nil &&
               model.roots.last?.location == SIMD2(340, 160))
        let prior = model.roots, primary = model.selected, ids = model.selectedIDs
        func unchanged(_ result: Bool) {
            assert(!result && model.roots == prior && model.selected == primary && model.selectedIDs == ids,
                   "Rejected insertion must not touch roots or selection")
        }
        unchanged(model.insertRoot(title: "both", image: image, video: video, at: CGPoint.zero))
        unchanged(model.insertRoot(title: String(repeating: "界", count: 21_846), at: CGPoint.zero))
        unchanged(model.insertRoot(title: "out", at: CGPoint(x: 1_000_001, y: 0)))
        unchanged(model.insertRoot(title: "nan", at: CGPoint(x: CGFloat.nan, y: 1)))
        unchanged(model.insertRoot(title: "infinite", at: CGPoint(x: 0, y: CGFloat.infinity)))
        assert(model.undo() && model.roots == imageBefore && model.selectedIDs.isEmpty,
               "Rejected inserts cannot produce extra undo steps")
        assert(model.redo() && model.roots == prior && model.selectedIDs == ids,
               "A rejected insert must preserve the normal redo path")
        assert(model.undo() && model.roots == imageBefore)
        assert(model.selectOnly(a.children[0].id))
        model.addChild()
        assert(model.roots[0].children[0].children.count == 1 && model.roots.count == imageBefore.count,
               "Re-selecting a child preserves explicit child insertion")
        let boundary = MapModel(roots: [a], selected: a.id)
        assert(boundary.clearSelection())
        assert(boundary.insertRoot(title: String(repeating: "x", count: 65_536),
                                   at: CGPoint(x: 1_000_000, y: -1_000_000)))
        assert(boundary.roots.last?.location == SIMD2(1_000_000, -1_000_000) && boundary.undo())
        let oversized = MapNode(id: UUID(), title: String(repeating: "x", count: MapModel.maxSavedJSONBytes),
                                children: [], folded: false)
        let budget = MapModel(roots: [oversized], selected: oversized.id)
        assert(!budget.insertRoot(title: "over limit", at: CGPoint.zero) &&
               budget.roots.count == 1 && budget.selected == oversized.id && !budget.undo(),
               "Projected Own JSON beyond 32 MiB cannot mutate or save a partial root")
        let noSelectionRoot = MapModel(roots: [a, b], selected: a.id)
        assert(noSelectionRoot.clearSelection())
        noSelectionRoot.addMainNode()
        assert(noSelectionRoot.roots.count == 3 && noSelectionRoot.roots[0] == a &&
               noSelectionRoot.roots[1] == b && noSelectionRoot.selected == noSelectionRoot.roots[2].id,
               "Intentional root creation appends, never indexes from stale primary")
        print("blank selection, atomic independent text/image/video root insertion and undo passed")
    }

    static func tinyImage() throws -> MapImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return try MapImage(data: bitmap.representation(using: .png, properties: [:])!)
    }

    static func tinyVideo() async throws -> MapVideo {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let scratch = base.appendingPathComponent("blank-root-video-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard scratch.deletingLastPathComponent() == base, lstat(scratch.path, &info) == 0,
              info.st_uid == getuid(), info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { throw MapVideoError.invalidData }
        let inode = info.st_ino
        defer {
            var current = stat()
            if scratch.deletingLastPathComponent() == base,
               scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
               lstat(scratch.path, &current) == 0, current.st_ino == inode,
               current.st_uid == getuid(), current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                try? FileManager.default.removeItem(at: scratch)
            }
        }
        let source = scratch.appendingPathComponent("generated.mov")
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 32])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                          kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 32])
        writer.add(input)
        guard writer.startWriting() else { throw MapVideoError.invalidData }
        writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 32, kCVPixelFormatType_32ARGB,
                                  nil, &pixel) == kCVReturnSuccess, let pixel,
              adaptor.append(pixel, withPresentationTime: .zero),
              adaptor.append(pixel, withPresentationTime: CMTime(value: 1, timescale: 30)) else {
            throw MapVideoError.invalidData
        }
        input.markAsFinished()
        await withCheckedContinuation { done in writer.finishWriting { done.resume() } }
        guard writer.status == .completed else { throw MapVideoError.invalidData }
        return try MapVideo(data: Data(contentsOf: source))
    }
}
