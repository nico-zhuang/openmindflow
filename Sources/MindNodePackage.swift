import Foundation
import Darwin

enum MindNodePackage {
    enum CopyError: Error { case unsupported }

    static func copyUnmodified(from source: URL, to destination: URL) throws {
        try copy(from: source, to: destination, editedRoots: nil)
    }

    static func copyUpdatingExistingNodes(from source: URL, to destination: URL, editedRoots: [MapNode]) throws {
        try copy(from: source, to: destination, editedRoots: editedRoots)
    }

    // ponytail: path-based copy assumes a stable trusted sibling directory; use dirfd/openat traversal before exposing writes for concurrently mutable user packages.
    private static func copy(from source: URL, to destination: URL, editedRoots: [MapNode]?) throws {
        let fm = FileManager.default
        let source = source.standardizedFileURL, destination = destination.standardizedFileURL
        let parent = source.deletingLastPathComponent()
        guard source.isFileURL, destination.isFileURL,
              source.pathExtension.lowercased() == "mindnode",
              destination.pathExtension.lowercased() == "mindnode",
              destination.deletingLastPathComponent() == parent, destination != source else {
            throw CopyError.unsupported
        }
        var info = stat()
        guard lstat(parent.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              lstat(source.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw CopyError.unsupported
        }
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parentFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = close(parentFD) }
        guard fstatat(parentFD, destination.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else { throw CopyError.unsupported }
        let originalRoots = try MindNodeImporter.load(source)
        let original = try manifest(source)

        var pattern = (parent.path + "/.mindmap-copy-XXXXXX").utf8CString
        let stagePath = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let created = mkdtemp(start) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return String(cString: created)
        }
        let stage = URL(fileURLWithPath: stagePath, isDirectory: true)
        guard lstat(stage.path, &info) == 0 else { throw CopyError.unsupported }
        let stageInode = info.st_ino
        defer {
            var current = stat()
            if stage.deletingLastPathComponent() == parent,
               stage.resolvingSymlinksInPath().standardizedFileURL == stage,
               lstat(stage.path, &current) == 0, current.st_ino == stageInode,
               current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                try? fm.removeItem(at: stage)
            }
        }
        let payload = stage.appendingPathComponent("payload.mindnode", isDirectory: true)
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL | COPYFILE_NOFOLLOW)
        guard copyfile(source.path, payload.path, nil, flags) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let staged = try manifest(payload)
        let sourceAfterCopy = try manifest(source)
        guard staged.0 == original.0, staged.1 == original.1,
              sourceAfterCopy.0 == original.0, sourceAfterCopy.1 == original.1 else {
            throw CopyError.unsupported
        }
        if let editedRoots {
            guard let contents = original.1["contents.xml"] else { throw CopyError.unsupported }
            let patched = try MindNodeTitlePatch.apply(to: contents, original: originalRoots, edited: editedRoots)
            if patched != contents {
                try patched.write(to: payload.appendingPathComponent("contents.xml")) // Only the private stage changes.
            }
            let updated = try manifest(payload)
            guard updated.0 == original.0,
                  updated.1.filter({ $0.key != "contents.xml" }) == original.1.filter({ $0.key != "contents.xml" }),
                  try MindNodeImporter.load(payload) == editedRoots else { throw CopyError.unsupported }
        } else {
            _ = try MindNodeImporter.load(payload)
        }
        let relative = stage.lastPathComponent + "/payload.mindnode"
        guard renameatx_np(parentFD, relative, parentFD, destination.lastPathComponent,
                           UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    // ponytail: 64 MiB in-memory snapshot; stream hashes when resource-heavy packages are supported.
    private static func manifest(_ root: URL) throws -> (Set<String>, [String: Data]) {
        let fm = FileManager.default
        guard let rootPointer = realpath(root.path, nil) else { throw CopyError.unsupported }
        defer { free(rootPointer) }
        let rootPrefix = String(cString: rootPointer) + "/"
        var paths = Set<String>()
        var files = [String: Data]()
        var scanError: Error?
        guard let items = fm.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: {
            _, error in scanError = error; return false
        }) else { throw CopyError.unsupported }
        var total = 0
        while let url = items.nextObject() as? URL {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw CopyError.unsupported }
            let type = info.st_mode & mode_t(S_IFMT)
            guard type == mode_t(S_IFDIR) || type == mode_t(S_IFREG), paths.count < 1_000 else {
                throw CopyError.unsupported
            }
            guard let itemPointer = realpath(url.path, nil) else { throw CopyError.unsupported }
            let itemPath = String(cString: itemPointer)
            free(itemPointer)
            guard itemPath.hasPrefix(rootPrefix) else { throw CopyError.unsupported }
            let relative = String(itemPath.dropFirst(rootPrefix.count))
            guard !relative.isEmpty, paths.insert(relative).inserted else { throw CopyError.unsupported }
            if type == mode_t(S_IFREG) {
                guard info.st_size >= 0, info.st_size <= 64 * 1024 * 1024 - total else {
                    throw CopyError.unsupported
                }
                let data = try Data(contentsOf: url)
                total += data.count
                guard total <= 64 * 1024 * 1024 else { throw CopyError.unsupported }
                files[relative] = data
            }
        }
        if let scanError { throw scanError }
        return (paths, files)
    }
}
