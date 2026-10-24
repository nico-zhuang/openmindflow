import AppKit
import AVFoundation
import AVKit
import Darwin

// ponytail: embedded clips top out at 16 MiB; use a portable sidecar when ordinary large videos matter.
enum MapVideoError: LocalizedError {
    case tooLarge, invalidFormat, invalidData, invalidDimensions

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "An embedded video must be 16 MiB or smaller; larger videos are not supported yet."
        case .invalidFormat: return "Use a playable MP4, MOV, or M4V video."
        case .invalidData: return "The video is damaged, has no playable video track, or has no finite duration."
        case .invalidDimensions: return "A video must be at most 4096 pixels per side and 16 million pixels total."
        }
    }
}

private final class MapVideoTemporaryFile {
    let url: URL
    private let inode: ino_t

    init(data: Data) throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let candidate = base.appendingPathComponent("mindmap-video-\(UUID().uuidString).mov")
        guard candidate.deletingLastPathComponent() == base else { throw MapVideoError.invalidData }
        let fd = open(candidate.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(fd)
            unlink(candidate.path)
            throw error
        }
        inode = info.st_ino
        url = candidate
        do {
            let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try file.write(contentsOf: data)
            try file.close()
        } catch {
            unlink(candidate.path)
            throw error
        }
    }

    deinit {
        var info = stat()
        if lstat(url.path, &info) == 0, info.st_ino == inode, info.st_uid == getuid(),
           info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) { unlink(url.path) }
    }
}

struct MapVideo: Codable, Equatable {
    static let maxEmbeddedBytes = 16 * 1024 * 1024
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: Double

    init(data: Data) throws {
        guard data.count <= Self.maxEmbeddedBytes else { throw MapVideoError.tooLarge }
        guard data.count >= 12, data[data.startIndex + 4..<data.startIndex + 8].elementsEqual("ftyp".utf8) else {
            throw MapVideoError.invalidFormat
        }
        let temporary = try MapVideoTemporaryFile(data: data)
        let asset = AVURLAsset(url: temporary.url)
        guard asset.isPlayable, let track = asset.tracks(withMediaType: .video).first else {
            throw MapVideoError.invalidData
        }
        let size = track.naturalSize.applying(track.preferredTransform)
        guard size.width.isFinite, size.height.isFinite,
              (1...4096).contains(abs(size.width)), (1...4096).contains(abs(size.height)) else {
            throw MapVideoError.invalidDimensions
        }
        let width = Int(abs(size.width.rounded())), height = Int(abs(size.height.rounded()))
        guard width * height <= 16_000_000 else {
            throw MapVideoError.invalidDimensions
        }
        let seconds = asset.duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw MapVideoError.invalidData }
        let generator = AVAssetImageGenerator(asset: asset)
        guard (try? generator.copyCGImage(at: .zero, actualTime: nil)) != nil else { throw MapVideoError.invalidData }
        self.data = data
        pixelWidth = width
        pixelHeight = height
        duration = seconds
    }

    func displaySize(width: CGFloat? = nil) -> CGSize {
        let ratio = CGFloat(pixelWidth) / CGFloat(pixelHeight)
        let fitted = min(296, CGFloat(pixelWidth), 296 * ratio)
        let actualWidth = min(width ?? fitted, 1000 * ratio)
        return CGSize(width: actualWidth, height: actualWidth / ratio)
    }

    private enum CodingKeys: String, CodingKey { case data }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(data: container.decode(Data.self, forKey: .data))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
    }
}

final class MapVideoPlayerView: AVPlayerView {
    private let mediaFile: MapVideoTemporaryFile

    init(video: MapVideo) throws {
        mediaFile = try MapVideoTemporaryFile(data: video.data)
        super.init(frame: .zero)
        controlsStyle = .inline // Native play/pause and scrubber; App supplies the title below.
        player = AVPlayer(url: mediaFile.url)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view only") }
}
