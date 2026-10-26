import AppKit
import AVFoundation
import Darwin

@main
enum CanvasVideoDropTests {
    static func main() async throws {
        _ = NSApplication.shared // Safe offscreen synthetic media; never access a running application.
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let folder = base.appendingPathComponent("openmindflow-video-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        var initial = stat()
        guard folder.deletingLastPathComponent() == base,
              folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
              lstat(folder.path, &initial) == 0, initial.st_uid == getuid(),
              initial.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              initial.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Unsafe synthetic folder") }
        defer {
            var current = stat()
            if folder.deletingLastPathComponent() == base,
               folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
               lstat(folder.path, &current) == 0, current.st_uid == getuid(),
               current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) { try? FileManager.default.removeItem(at: folder) }
        }
        let source = folder.appendingPathComponent("synthetic.mov")
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 32
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                          kCVPixelBufferWidthKey as String: 64,
                                          kCVPixelBufferHeightKey as String: 32])
        writer.add(input)
        assert(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        assert(CVPixelBufferCreate(kCFAllocatorDefault, 64, 32, kCVPixelFormatType_32ARGB,
                                   nil, &pixel) == kCVReturnSuccess)
        assert(adaptor.append(pixel!, withPresentationTime: .zero))
        assert(adaptor.append(pixel!, withPresentationTime: CMTime(value: 1, timescale: 30)))
        input.markAsFinished()
        await withCheckedContinuation { done in writer.finishWriting { done.resume() } }
        assert(writer.status == .completed)
        let bytes = try Data(contentsOf: source)
        assert((try? MapVideo(data: bytes)) != nil)
        let root = MapNode(id: UUID(), title: "Original", children: [], folded: false,
                           location: SIMD2(130, 220))
        let canvas = MapCanvas(model: MapModel(roots: [root], selected: root.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 720)
        let board = NSPasteboard(name: .init("openmindflow-movie-file-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        assert(board.setString(source.absoluteString, forType: .fileURL))
        let blank = CGPoint(x: 880, y: 590)
        assert(canvas.acceptDroppedMedia(from: board, at: blank), "Finder movie file must drop onto blank canvas")
        assert(canvas.model.roots.count == 2 && canvas.model.roots[0] == root &&
               canvas.model.roots[1].video?.data == bytes &&
               canvas.model.roots[1].location == SIMD2(800, 500),
               "Video drop must embed verified bytes in independent root at world position")
        canvas.undo()
        assert(canvas.model.roots == [root])
        canvas.model.clearSelection()
        canvas.paste(from: board)
        assert(canvas.model.roots.count == 2 && canvas.model.roots[1].video?.data == bytes,
               "Pasting an external movie file URL with no selection creates independent root")
        canvas.undo()
        assert(canvas.model.selectedIDs.isEmpty)
        let nodePoint = canvas.frameForAccessibility(root.id)!
        assert(canvas.acceptDroppedMedia(from: board, at: CGPoint(x: nodePoint.midX, y: nodePoint.midY)))
        assert(canvas.model.roots.count == 1 && canvas.model.roots[0].children.count == 1 &&
               canvas.model.roots[0].children[0].video?.data == bytes,
               "Movie dropped onto visible node becomes that node's child")
        canvas.undo()
        let huge = folder.appendingPathComponent("oversized.mov")
        FileManager.default.createFile(atPath: huge.path, contents: Data())
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(MapVideo.maxEmbeddedBytes + 1))
        try handle.close()
        board.clearContents()
        assert(board.setString(huge.absoluteString, forType: .fileURL))
        var videoErrors = 0, imageErrors = 0
        canvas.onVideoError = { _ in videoErrors += 1 }
        canvas.onImageError = { _ in imageErrors += 1 }
        let prior = canvas.model.roots, selection = canvas.model.selectedIDs
        assert(!canvas.acceptDroppedMedia(from: board, at: blank) &&
               canvas.model.roots == prior && canvas.model.selectedIDs == selection,
               "Oversized movie must be rejected before reading or modifying selection")
        assert(videoErrors == 1 && imageErrors == 0,
               "Rejected movie file must explain a video import failure, not a mistaken image failure")
        print("Finder movie drop/paste, blank root, target child, media limit and Undo passed")
    }
}
