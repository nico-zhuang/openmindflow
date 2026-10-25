import AppKit
import AVFoundation
import AVKit
import Darwin

@main
enum VideoCanvasTests {
    static func main() async throws {
        _ = NSApplication.shared // Offscreen only: no window, original app, or global events.
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let folder = base.appendingPathComponent("video-canvas-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard folder.deletingLastPathComponent() == base,
              folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
              lstat(folder.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else {
            fatalError("Synthetic video directory must be owned 0700")
        }
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = folder.appendingPathComponent("synthetic.mov")
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 32
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 32
            ])
        writer.add(input)
        assert(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        assert(CVPixelBufferCreate(kCFAllocatorDefault, 64, 32, kCVPixelFormatType_32ARGB,
                                   nil, &pixel) == kCVReturnSuccess)
        assert(adaptor.append(pixel!, withPresentationTime: .zero))
        assert(adaptor.append(pixel!, withPresentationTime: CMTime(value: 1, timescale: 30)))
        input.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        assert(writer.status == .completed)
        let video = try MapVideo(data: Data(contentsOf: source))
        assert(video.data.count <= MapVideo.maxEmbeddedBytes)

        let rootID = UUID()
        let root = MapNode(id: rootID, title: "Media map", children: [], folded: false)
        let model = MapModel(roots: [root], selected: rootID)
        assert(model.addVideoChild(video) && model.roots[0].children.count == 1)
        let childID = model.selected
        assert(model.roots[0].children[0].id == childID)
        assert(model.roots[0].children[0].video == video && model.roots[0].children[0].image == nil)
        assert(model.roots[0].children[0].title.isEmpty, "Video caption is optional")
        assert(exportMarkdown(model.roots).contains("[Video omitted]") &&
               exportMarkdown(model.roots).contains("not embedded"),
               "Markdown must explicitly disclose that titleless video bytes are not in the export")
        assert(model.undo() && model.roots == [root] && model.selected == rootID,
               "Add video child and select it in one undo step")
        assert(model.redo() && model.selected == childID)
        assert(model.setVideoWidth(240) && model.roots[0].children[0].videoWidth == 240)
        assert(!model.setVideoWidth(59) && !model.setVideoWidth(1001) && !model.setVideoWidth(CGFloat.nan))
        model.rename("行程影片 🎬")
        let titled = mapLayout(model.roots).first { $0.node.id == childID }!.frame
        var noTitle = model.roots[0]
        noTitle.children[0].title = ""
        let plain = mapLayout([noTitle]).first { $0.node.id == childID }!.frame
        assert(titled.height > plain.height && titled.width >= 264,
               "Video preserves aspect ratio and reserves caption space only when titled")
        assert(model.undo() && model.roots[0].children[0].title.isEmpty)
        assert(model.redo() && model.roots[0].children[0].title == "行程影片 🎬")

        let fileModel = MapModel(roots: [root], selected: rootID)
        let fileCanvas = MapCanvas(model: fileModel)
        try fileCanvas.insertVideoFile(source)
        assert(fileModel.roots[0].children[0].video == video, "File import must embed bytes, not an external path")
        let board = NSPasteboard(name: .init("local.mindmap.synthetic-video-\(UUID().uuidString)"))
        board.clearContents()
        assert(board.setString(source.absoluteString, forType: .fileURL))
        let pasteModel = MapModel(roots: [root], selected: rootID)
        let pasteCanvas = MapCanvas(model: pasteModel)
        assert(pasteCanvas.pasteVideoFromPasteboard(board) && pasteModel.roots[0].children[0].video == video,
               "Pasting a video file URL must also embed validated bytes")
        let document = OwnMapDocument(roots: model.roots)
        let url = folder.appendingPathComponent("media.mindmap.json")
        try writeOwnDocument(document, to: url)
        let reopened = try readOwnDocument(url)
        assert(reopened.roots == model.roots && reopened.roots[0].children[0].video == video)
        var mediaInfo = stat()
        guard source.deletingLastPathComponent() == folder,
              source.resolvingSymlinksInPath().standardizedFileURL == source.standardizedFileURL,
              lstat(source.path, &mediaInfo) == 0, mediaInfo.st_uid == getuid(),
              mediaInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            fatalError("Only the owned synthetic media file can be removed")
        }
        try FileManager.default.removeItem(at: source) // The persisted document must own its video bytes.
        let reopenedModel = MapModel(roots: reopened.roots, selected: childID)
        var untitledVideo = reopened.roots
        untitledVideo[0].children[0].title = ""
        let mediaOutline = MapOutlineView(canvas: MapCanvas(model: MapModel(roots: untitledVideo, selected: childID)))
        let mediaRow = mediaOutline.outlineView.item(atRow: 1)!
        let mediaLabel = mediaOutline.outlineView(mediaOutline.outlineView, viewFor: nil, item: mediaRow) as! NSTextField
        assert(mediaLabel.stringValue == L10n.text("Video"),
               "Untitled video must be identifiable in native outline rather than mislabeled New idea")
        let canvas = MapCanvas(model: reopenedModel)
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let stillOutput = folder.appendingPathComponent("saved-video-still.png")
        try exportMap(canvas, as: .png, to: stillOutput)
        let still = NSBitmapImageRep(data: try Data(contentsOf: stillOutput))
        assert((still?.pixelsWide ?? 0) > 0 && (still?.pixelsHigh ?? 0) > 0,
               "Detached full-map PNG must export saved video without an original MOV file")
        let media = canvas.mediaRect(for: childID)!
        let caption = canvas.mediaTitleRect(for: childID)!
        assert(abs(media.width / media.height - 2) < 0.01 && media.width >= 240)
        assert(caption.minY >= media.maxY + 7 && caption.width > 0,
               "Caption geometry stays below rather than over the video")
        let mouse = NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: media.midX, y: canvas.bounds.height - media.midY),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        canvas.mouseDown(with: mouse)
        let player = canvas.subviews.compactMap { $0 as? MapVideoPlayerView }.first
        assert(player?.player?.currentItem != nil && player?.controlsStyle == .inline,
               "Clicking persisted video shows native player with play and progress/seek controls")
        assert(canvas.playVideo(childID) && canvas.subviews.compactMap { $0 as? MapVideoPlayerView }.count == 1,
               "Direct play uses the same native player as the click path")
        await player?.player?.seek(to: CMTime(value: 1, timescale: 60))
        player?.player?.play()
        player?.player?.pause()

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = try MapImage(data: bitmap.representation(using: .png, properties: [:])!)
        assert(reopenedModel.setImage(image))
        assert(reopenedModel.roots[0].children[0].video == nil && reopenedModel.roots[0].children[0].image == image,
               "An image replaces video rather than storing two active media on one node")
        assert(reopenedModel.undo() && reopenedModel.roots[0].children[0].video == video)

        let oversizedRoot = MapNode(id: UUID(), title: String(repeating: "x", count: MapModel.maxSavedJSONBytes),
                                    children: [], folded: false)
        let oversized = MapModel(roots: [oversizedRoot], selected: oversizedRoot.id)
        assert(!oversized.addVideoChild(video) && oversized.roots == [oversizedRoot],
               "A video cannot create an unsavable >32 MiB document or partial undo")
        print("video node add, resize, caption, file/clipboard import, JSON reopen, native player and budget passed (offscreen)")
    }
}
