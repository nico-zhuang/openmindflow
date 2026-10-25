import AppKit
import AVFoundation
import AVKit
import Darwin

@main
enum MapVideoTests {
    static func main() async throws {
        _ = NSApplication.shared // No window or event loop.
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let scratch = base.appendingPathComponent("map-video-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
              scratch.deletingLastPathComponent() == base,
              lstat(scratch.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Unsafe synthetic fixture directory") }
        let ownedInode = info.st_ino
        defer {
            var current = stat()
            if scratch.deletingLastPathComponent() == base,
               scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
               lstat(scratch.path, &current) == 0, current.st_ino == ownedInode,
               current.st_uid == getuid(), current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                try? FileManager.default.removeItem(at: scratch)
            }
        }
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
        var mediaInfo = stat()
        guard source.deletingLastPathComponent() == scratch,
              source.resolvingSymlinksInPath().standardizedFileURL == source.standardizedFileURL,
              lstat(source.path, &mediaInfo) == 0, mediaInfo.st_uid == getuid(),
              mediaInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            fatalError("Only the owned synthetic MOV may be removed")
        }
        try FileManager.default.removeItem(at: source)
        assert(reopened.posterImage() != nil, "A static map export needs a still frame after the source MOV disappears")
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
