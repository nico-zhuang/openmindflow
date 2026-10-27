import AppKit
import AVFoundation
import Darwin

@main enum CanvasRootVideoReparentTests {
    static func main() async throws {
        _ = NSApplication.shared // Synthetic 2-frame MOV and detached canvas; no user media or GUI.
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let folder = base.appendingPathComponent("openmindflow-root-video-drag-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: 0o700])
        var initial = stat()
        guard folder.deletingLastPathComponent() == base,
              folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
              lstat(folder.path, &initial) == 0, initial.st_uid == getuid(),
              initial.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              initial.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Unsafe private fixture") }
        defer {
            var current = stat()
            if folder.deletingLastPathComponent() == base,
               folder.resolvingSymlinksInPath().standardizedFileURL == folder.standardizedFileURL,
               lstat(folder.path, &current) == 0, current.st_uid == getuid(),
               current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                try? FileManager.default.removeItem(at: folder)
            }
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
        let target = MapNode(id: UUID(), title: "Video target child", children: [], folded: false)
        let main = MapNode(id: UUID(), title: "Main", children: [target], folded: false,
                           location: SIMD2(150, 180))
        let canvas = MapCanvas(model: MapModel(roots: [main], selected: main.id))
        canvas.frame = CGRect(x: 0, y: 0, width: 1400, height: 800)
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: canvas.bounds.height - point.y),
                               modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let blank = CGPoint(x: 1080, y: 170)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: blank))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: blank))
        let board = NSPasteboard(name: .init("openmindflow-private-root-video-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        assert(board.setString(source.absoluteString, forType: .fileURL) && canvas.paste(from: board))
        let clipID = canvas.model.roots.last!.id
        assert(canvas.model.roots.count == 2 && canvas.model.roots.last?.video?.data == bytes)
        let poster = canvas.mediaRect(for: clipID)!
        let grab = CGPoint(x: poster.midX, y: poster.midY)
        let destination = canvas.frameForAccessibility(target.id)!
        let hover = CGPoint(x: destination.midX, y: destination.midY)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: grab))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: hover))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: hover))
        guard canvas.model.roots.count == 1,
              canvas.model.roots[0].children[0].children.first?.id == clipID,
              canvas.model.roots[0].children[0].children.first?.video?.data == bytes else {
            fatalError("Drag from a pasted video poster must attach it beneath the hovered target")
        }
        assert(!canvas.frameForAccessibility(clipID)!.intersects(canvas.frameForAccessibility(target.id)!),
               "A committed video child cannot cover its parent")
        canvas.undo()
        assert(canvas.model.roots.count == 2 && canvas.model.roots.last?.id == clipID,
               "Undo restores the independent video root")
        print("pasted video poster drag, attach as child, final non-overlap and Undo passed")
    }
}
