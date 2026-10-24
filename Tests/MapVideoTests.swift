import AppKit
import AVFoundation
import AVKit

@main
enum MapVideoTests {
    static func main() async throws {
        _ = NSApplication.shared // No window or event loop.
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let scratch = base.appendingPathComponent("map-video-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        guard scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
              scratch.deletingLastPathComponent() == base else { fatalError("Unsafe synthetic fixture directory") }
        defer { try? FileManager.default.removeItem(at: scratch) }
        let source = scratch.appendingPathComponent("synthetic.mov")
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
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 64, 32, kCVPixelFormatType_32ARGB,
                                         nil, &pixel)
        assert(result == kCVReturnSuccess && pixel != nil)
        assert(adaptor.append(pixel!, withPresentationTime: .zero))
        assert(adaptor.append(pixel!, withPresentationTime: CMTime(value: 1, timescale: 30)))
        input.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        assert(writer.status == .completed, "Generate synthetic playable frames without user files")
        let bytes = try Data(contentsOf: source)
        let video = try MapVideo(data: bytes)
        assert(video.pixelWidth == 64 && video.pixelHeight == 32 && video.duration > 0)
        assert(video.displaySize(width: 240) == CGSize(width: 240, height: 120))
        let persisted = try JSONEncoder().encode(video)
        let reopened = try JSONDecoder().decode(MapVideo.self, from: persisted)
        assert(reopened == video)
        try FileManager.default.removeItem(at: source)
        let playerView = try MapVideoPlayerView(video: reopened)
        assert(playerView.player?.currentItem != nil && playerView.controlsStyle == .inline,
               "Saved bytes must play through native controls without original path")
        playerView.player?.play()
        playerView.player?.pause()
        func rejects(_ action: () throws -> Void) {
            do { try action(); fatalError("Expected unsafe video to fail") } catch { }
        }
        rejects { _ = try MapVideo(data: Data()) }
        rejects { _ = try MapVideo(data: Data("fake video".utf8)) }
        rejects { _ = try MapVideo(data: Data(repeating: 0, count: 16 * 1024 * 1024 + 1)) }
        let badJSON = "{\"data\":\"\(Data("fake video".utf8).base64EncodedString())\"}"
        rejects { _ = try JSONDecoder().decode(MapVideo.self, from: Data(badJSON.utf8)) }
        print("synthetic video validation, JSON reopen, native player and limits passed (no windows)")
    }
}
