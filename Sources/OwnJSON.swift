import Foundation
import Darwin

private let ownJSONLimit = 32 * 1024 * 1024

enum OwnJSONError: LocalizedError {
    case invalidPath, invalidFile, tooLarge, duplicateID, invalidWidth, invalidLocation, invalidFont, invalidStyle, invalidImageSize

    var errorDescription: String? {
        switch self {
        case .invalidPath: return "Choose a .mindmap.json file."
        case .invalidFile: return "The document must be a regular file."
        case .tooLarge: return "The document exceeds the 32 MiB limit."
        case .duplicateID: return "The document contains duplicate node IDs."
        case .invalidWidth: return "A node width must be a finite value from 60 to 1000 points."
        case .invalidLocation: return "A saved node position must be within one million points."
        case .invalidFont: return "A font name must be at most 128 bytes and a font size from 1 to 512 points."
        case .invalidStyle: return "Alignment, line color, width or dash style is invalid."
        case .invalidImageSize: return "An image display width must be 60 to 1000 points and requires an image."
        }
    }
}

private func checkOwnJSONPath(_ url: URL) throws {
    guard url.isFileURL, url.lastPathComponent.hasSuffix(".mindmap.json") else { throw OwnJSONError.invalidPath }
}

private func checkOwnJSONNodes(_ roots: [MapNode]) throws {
    var ids = Set<UUID>()
    func visit(_ nodes: [MapNode]) throws {
        for node in nodes {
            guard ids.insert(node.id).inserted else { throw OwnJSONError.duplicateID }
            if let width = node.width {
                guard MapNode.validWidth(width) else { throw OwnJSONError.invalidWidth }
            }
            if let width = node.imageWidth,
               (node.image == nil || !width.isFinite || !(60...1000).contains(width)) {
                throw OwnJSONError.invalidImageSize
            }
            if let family = node.fontFamily, (family.isEmpty || family.utf8.count > 128) {
                throw OwnJSONError.invalidFont
            }
            if let size = node.fontSize, (!size.isFinite || !(1...512).contains(size)) {
                throw OwnJSONError.invalidFont
            }
            if let alignment = node.textAlignment,
               !["left", "center", "right", "justify"].contains(alignment) { throw OwnJSONError.invalidStyle }
            if let line = node.branchStrokeWidth,
               (!line.isFinite || !(0.5...16).contains(line)) { throw OwnJSONError.invalidStyle }
            if let color = node.branchStrokeColor,
               (color.count != 9 || color.first != "#" || UInt32(color.dropFirst(), radix: 16) == nil) {
                throw OwnJSONError.invalidStyle
            }
            if let style = node.strokeStyle,
               style != "solid" && style != "dashed" { throw OwnJSONError.invalidStyle }
            if let point = node.location {
                guard point.x.isFinite, point.y.isFinite,
                      abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000 else {
                    throw OwnJSONError.invalidLocation
                }
            }
            try visit(node.children)
        }
    }
    try visit(roots)
}

func readOwnJSON(_ url: URL) throws -> [MapNode] {
    try checkOwnJSONPath(url)
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw OwnJSONError.invalidFile }
    guard info.st_size <= ownJSONLimit else { throw OwnJSONError.tooLarge }
    var data = Data()
    while let chunk = try file.read(upToCount: ownJSONLimit + 1 - data.count), !chunk.isEmpty {
        data.append(chunk)
        if data.count > ownJSONLimit { throw OwnJSONError.tooLarge }
    }
    let roots = try JSONDecoder().decode([MapNode].self, from: data)
    try checkOwnJSONNodes(roots)
    return roots
}

func writeOwnJSON(_ roots: [MapNode], to url: URL) throws {
    try checkOwnJSONPath(url)
    try checkOwnJSONNodes(roots)
    let data = try JSONEncoder().encode(roots)
    guard data.count <= ownJSONLimit else { throw OwnJSONError.tooLarge }
    var info = stat()
    if lstat(url.path, &info) == 0 {
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw OwnJSONError.invalidFile }
    } else if errno != ENOENT {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try data.write(to: url, options: .atomic)
}
