import Foundation
import Darwin

private let ownJSONLimit = 8 * 1024 * 1024

enum OwnJSONError: LocalizedError {
    case invalidPath, invalidFile, tooLarge, duplicateID

    var errorDescription: String? {
        switch self {
        case .invalidPath: return "Choose a .mindmap.json file."
        case .invalidFile: return "The document must be a regular file."
        case .tooLarge: return "The document exceeds the 8 MiB limit."
        case .duplicateID: return "The document contains duplicate node IDs."
        }
    }
}

private func checkOwnJSONPath(_ url: URL) throws {
    guard url.isFileURL, url.lastPathComponent.hasSuffix(".mindmap.json") else { throw OwnJSONError.invalidPath }
}

private func checkOwnJSONIDs(_ roots: [MapNode]) throws {
    var ids = Set<UUID>()
    func visit(_ nodes: [MapNode]) throws {
        for node in nodes {
            guard ids.insert(node.id).inserted else { throw OwnJSONError.duplicateID }
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
    try checkOwnJSONIDs(roots)
    return roots
}

func writeOwnJSON(_ roots: [MapNode], to url: URL) throws {
    try checkOwnJSONPath(url)
    try checkOwnJSONIDs(roots)
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
