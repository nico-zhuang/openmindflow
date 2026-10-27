import Foundation
import Darwin

/// An owned, portable copy of one validated v9 source. No original path is retained.
struct MindNodeArchive: Codable {
    enum ArchiveError: LocalizedError {
        case unsafe
        var errorDescription: String? { "MindNode archive is unsafe, damaged, or contains edits this exporter cannot preserve." }
    }
    private struct Entry: Codable {
        let path: String
        let data: Data? // nil denotes an empty or nonempty directory.
    }
    private let version: Int
    private let directory: Bool
    private let entries: [Entry]
    let imported: MindNodeDetailedImport
    private static let limit = 64 * 1024 * 1024
    private static let maxDepth = 32

    init(importing source: URL) throws {
        guard source.isFileURL, source.pathExtension.lowercased() == "mindnode" else { throw ArchiveError.unsafe }
        let parent = source.deletingLastPathComponent().resolvingSymlinksInPath()
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parentFD >= 0 else { throw ArchiveError.unsafe }
        defer { _ = close(parentFD) }
        var st = stat()
        guard fstatat(parentFD, source.lastPathComponent, &st, AT_SYMLINK_NOFOLLOW) == 0 else { throw ArchiveError.unsafe }
        version = 1
        if st.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) {
            directory = false
            entries = [Entry(path: "", data: try Self.readFile(parentFD, source.lastPathComponent, remaining: Self.limit))]
        } else if st.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
            directory = true
            let fd = openat(parentFD, source.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0 else { throw ArchiveError.unsafe }
            defer { _ = close(fd) }
            var collected = [Entry](), remaining = Self.limit
            try Self.scan(fd, prefix: "", entries: &collected, remaining: &remaining)
            entries = collected.sorted { $0.path < $1.path }
        } else { throw ArchiveError.unsafe }
        try Self.validate(directory: directory, entries: entries)
        // Parse the owned snapshot, never the caller's potentially retargeted pathname.
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let temporaryFD = open(temporary.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard temporaryFD >= 0 else { throw ArchiveError.unsafe }
        defer { _ = close(temporaryFD) }
        let snapshot = try Self.stage(directory: directory, entries: entries, contents: nil,
                                      parentFD: temporaryFD, parentPath: temporary.path)
        defer { snapshot.cleanup() }
        imported = try MindNodeImporter.loadDetailed(snapshot.payloadURL)
        let second: MindNodeArchiveCapture = try Self.capture(source, parentFD: parentFD)
        guard second.directory == directory,
              second.entries.count == entries.count,
              zip(second.entries, entries).allSatisfy({ $0.path == $1.path && $0.data == $1.data }) else { throw ArchiveError.unsafe }
    }

    private final class Stage {
        let parentFD: Int32
        let name: String
        let fd: Int32
        let payloadURL: URL
        private struct Owned {
            let path: String
            let device: dev_t
            let inode: ino_t
            let directory: Bool
        }
        private var owned: [Owned] = []
        private var ownedDirectories: [String: Owned] = [:]
        private let inode: ino_t
        private let device: dev_t
        var published = false

        init(parentFD: Int32, parentPath: String) throws {
            self.parentFD = parentFD
            var created: String? = nil
            for _ in 0..<8 {
                let candidate = ".mindnode-archive-\(UUID().uuidString)"
                if mkdirat(parentFD, candidate, 0o700) == 0 { created = candidate; break }
                if errno != EEXIST { throw ArchiveError.unsafe }
            }
            guard let created else { throw ArchiveError.unsafe }
            name = created
            // Only the fresh empty directory may be removed if opening/fstat fails.
            var initial = stat()
            guard fstatat(parentFD, created, &initial, AT_SYMLINK_NOFOLLOW) == 0,
                  initial.st_uid == getuid(), initial.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
                throw ArchiveError.unsafe
            }
            func removeFreshEmptyDirectory() {
                var current = stat()
                if fstatat(parentFD, created, &current, AT_SYMLINK_NOFOLLOW) == 0,
                   current.st_dev == initial.st_dev, current.st_ino == initial.st_ino,
                   current.st_uid == getuid(), current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                    _ = unlinkat(parentFD, created, AT_REMOVEDIR)
                }
            }
            fd = openat(parentFD, created, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0 else { removeFreshEmptyDirectory(); throw ArchiveError.unsafe }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_dev == initial.st_dev,
                  info.st_ino == initial.st_ino, info.st_uid == getuid(),
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
                _ = close(fd)
                removeFreshEmptyDirectory()
                throw ArchiveError.unsafe
            }
            inode = info.st_ino
            device = info.st_dev
            payloadURL = URL(fileURLWithPath: parentPath + "/" + name + "/payload.mindnode")
        }

        // Traverse only directories created in this stage. Handles never survive an operation.
        private func openParent(of path: String) -> Int32? {
            let parent = path.split(separator: "/").dropLast()
            var current = dup(fd)
            guard current >= 0 else { return nil }
            var prefix = ""
            for component in parent {
                prefix += prefix.isEmpty ? String(component) : "/" + component
                guard let expected = ownedDirectories[prefix] else { _ = close(current); return nil }
                let next = openat(current, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                _ = close(current)
                guard next >= 0 else { return nil }
                var info = stat()
                guard fstat(next, &info) == 0, info.st_dev == expected.device,
                      info.st_ino == expected.inode, info.st_uid == getuid(),
                      info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
                    _ = close(next)
                    return nil
                }
                current = next
            }
            return current
        }

        func add(_ path: String, data: Data?) throws {
            guard let component = path.split(separator: "/").last.map(String.init),
                  let parent = openParent(of: path) else { throw ArchiveError.unsafe }
            defer { _ = close(parent) }
            let child: Int32
            if data != nil {
                child = openat(parent, component, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            } else {
                guard mkdirat(parent, component, 0o700) == 0 else { throw ArchiveError.unsafe }
                child = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            }
            guard child >= 0 else { throw ArchiveError.unsafe }
            defer { _ = close(child) }
            var info = stat()
            guard fstat(child, &info) == 0, info.st_uid == getuid(),
                  info.st_mode & mode_t(S_IFMT) == (data == nil ? mode_t(S_IFDIR) : mode_t(S_IFREG)) else {
                throw ArchiveError.unsafe
            }
            let item = Owned(path: path, device: info.st_dev, inode: info.st_ino, directory: data == nil)
            owned.append(item)
            if data == nil { ownedDirectories[path] = item }
            if let data {
                let written = data.withUnsafeBytes { bytes -> Bool in
                    guard let base = bytes.baseAddress else { return true }
                    var offset = 0
                    while offset < bytes.count {
                        let count = Darwin.write(child, base.advanced(by: offset), bytes.count - offset)
                        if count <= 0 { return false }
                        offset += count
                    }
                    return true
                }
                guard written else { throw ArchiveError.unsafe }
            }
        }

        func cleanup() {
            if !published {
                for item in owned.reversed() {
                    guard let parent = openParent(of: item.path),
                          let component = item.path.split(separator: "/").last else { continue }
                    var current = stat()
                    if fstatat(parent, String(component), &current, AT_SYMLINK_NOFOLLOW) == 0,
                       current.st_dev == item.device, current.st_ino == item.inode,
                       current.st_uid == getuid(),
                       current.st_mode & mode_t(S_IFMT) == (item.directory ? mode_t(S_IFDIR) : mode_t(S_IFREG)) {
                        _ = unlinkat(parent, String(component), item.directory ? AT_REMOVEDIR : 0)
                    }
                    _ = close(parent)
                }
            }
            var current = stat()
            if fstatat(parentFD, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
               current.st_dev == device, current.st_ino == inode, current.st_uid == getuid(),
               current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                _ = unlinkat(parentFD, name, AT_REMOVEDIR)
            }
            _ = close(fd)
        }
    }

    private static func stage(directory: Bool, entries: [Entry], contents: Data?,
                              parentFD: Int32, parentPath: String) throws -> Stage {
        let stage = try Stage(parentFD: parentFD, parentPath: parentPath)
        do {
            if directory {
                try stage.add("payload.mindnode", data: nil)
                for entry in entries where entry.data == nil { try stage.add("payload.mindnode/" + entry.path, data: nil) }
                for entry in entries where entry.data != nil {
                    try stage.add("payload.mindnode/" + entry.path,
                                  data: entry.path == "contents.xml" ? (contents ?? entry.data) : entry.data)
                }
            } else {
                try stage.add("payload.mindnode", data: contents ?? entries[0].data)
            }
            return stage
        } catch { stage.cleanup(); throw error }
    }

    private struct MindNodeArchiveCapture {
        let directory: Bool
        let entries: [Entry]
    }
    private static func capture(_ source: URL, parentFD: Int32) throws -> MindNodeArchiveCapture {
        var st = stat()
        guard fstatat(parentFD, source.lastPathComponent, &st, AT_SYMLINK_NOFOLLOW) == 0 else { throw ArchiveError.unsafe }
        if st.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) {
            return MindNodeArchiveCapture(directory: false, entries: [Entry(path: "", data: try readFile(parentFD, source.lastPathComponent, remaining: limit))])
        }
        guard st.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw ArchiveError.unsafe }
        let fd = openat(parentFD, source.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw ArchiveError.unsafe }
        defer { _ = close(fd) }
        var entries = [Entry](), remaining = limit
        try scan(fd, prefix: "", entries: &entries, remaining: &remaining)
        return MindNodeArchiveCapture(directory: true, entries: entries.sorted { $0.path < $1.path })
    }

    private static func readFile(_ dirFD: Int32, _ name: String, remaining: Int) throws -> Data {
        let fd = openat(dirFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw ArchiveError.unsafe }
        defer { _ = close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              st.st_size >= 0, st.st_size <= remaining else { throw ArchiveError.unsafe }
        var data = Data()
        while data.count <= remaining {
            var chunk = [UInt8](repeating: 0, count: min(64 * 1024, remaining - data.count + 1))
            let count = read(fd, &chunk, chunk.count)
            guard count >= 0 else { throw ArchiveError.unsafe }
            if count == 0 { break }
            data.append(contentsOf: chunk.prefix(count))
        }
        guard data.count <= remaining, data.count == st.st_size,
              fstat(fd, &st) == 0, st.st_size == data.count else { throw ArchiveError.unsafe }
        return data
    }

    private static func scan(_ fd: Int32, prefix: String, entries: inout [Entry], remaining: inout Int,
                             depth: Int = 0) throws {
        guard depth <= maxDepth else { throw ArchiveError.unsafe }
        let duplicate = dup(fd)
        guard duplicate >= 0, let stream = fdopendir(duplicate) else {
            if duplicate >= 0 { _ = close(duplicate) }
            throw ArchiveError.unsafe
        }
        defer { _ = closedir(stream) }
        while let item = readdir(stream) {
            let name = withUnsafePointer(to: item.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard safeComponent(name), entries.count < 1000 else { throw ArchiveError.unsafe }
            let path = prefix + name
            var st = stat()
            guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { throw ArchiveError.unsafe }
            switch st.st_mode & mode_t(S_IFMT) {
            case mode_t(S_IFDIR):
                entries.append(Entry(path: path, data: nil))
                let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard child >= 0 else { throw ArchiveError.unsafe }
                do { try scan(child, prefix: path + "/", entries: &entries, remaining: &remaining, depth: depth + 1) }
                catch { _ = close(child); throw error }
                _ = close(child)
            case mode_t(S_IFREG):
                let data = try readFile(fd, name, remaining: remaining)
                remaining -= data.count
                entries.append(Entry(path: path, data: data))
            default: throw ArchiveError.unsafe
            }
        }
    }
    private static func safeComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") &&
        !name.contains("\\") && !name.contains("\0") && name.utf8.count <= 255
    }
    private static func validate(directory: Bool, entries: [Entry]) throws {
        guard entries.count <= 1000, !entries.isEmpty else { throw ArchiveError.unsafe }
        var seen = Set<String>(), total = 0
        for entry in entries {
            if !directory {
                guard entries.count == 1, entry.path == "", let data = entry.data,
                      data.count <= limit else { throw ArchiveError.unsafe }
                return
            }
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count <= maxDepth, parts.allSatisfy(safeComponent),
                  seen.insert(entry.path).inserted else { throw ArchiveError.unsafe }
            if parts.count > 1 {
                let parent = parts.dropLast().joined(separator: "/")
                guard entries.contains(where: { $0.path == parent && $0.data == nil }) else { throw ArchiveError.unsafe }
            }
            if let data = entry.data {
                guard data.count <= limit - total else { throw ArchiveError.unsafe }
                total += data.count
            }
        }
        guard entries.first(where: { $0.path == "contents.xml" })?.data != nil else { throw ArchiveError.unsafe }
    }

    private enum CodingKeys: String, CodingKey { case version, directory, entries, imported }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        directory = try container.decode(Bool.self, forKey: .directory)
        entries = try container.decode([Entry].self, forKey: .entries)
        imported = try container.decode(MindNodeDetailedImport.self, forKey: .imported)
        guard version == 1 else { throw ArchiveError.unsafe }
        try Self.validate(directory: directory, entries: entries)
        let contents = directory ? entries.first(where: { $0.path == "contents.xml" })?.data : entries.first?.data
        guard let contents, (try? MindNodeTitlePatch.apply(to: contents, original: imported.roots, edited: imported.roots)) == contents else { throw ArchiveError.unsafe }
    }

    func export(document: OwnMapDocument, to destination: URL) throws {
        guard document.relationships.isEmpty, document.theme == nil,
              document.canvasColor == nil else { throw ArchiveError.unsafe }
        let editedRoots = document.roots
        try Self.validate(directory: directory, entries: entries)
        guard version == 1, destination.isFileURL, destination.pathExtension.lowercased() == "mindnode",
              !destination.lastPathComponent.contains("/"), Self.safeComponent(destination.lastPathComponent) else { throw ArchiveError.unsafe }
        let contents = directory ? entries.first(where: { $0.path == "contents.xml" })!.data! : entries[0].data!
        let patched = try MindNodeTitlePatch.apply(to: contents, original: imported.roots, edited: editedRoots)
        let parent = destination.deletingLastPathComponent()
        var st = stat()
        guard lstat(parent.path, &st) == 0, st.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              st.st_uid == getuid(), st.st_mode & mode_t(0o022) == 0 else { throw ArchiveError.unsafe }
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parentFD >= 0 else { throw ArchiveError.unsafe }
        defer { _ = close(parentFD) }
        var openedParent = stat()
        guard fstat(parentFD, &openedParent) == 0, openedParent.st_dev == st.st_dev,
              openedParent.st_ino == st.st_ino, openedParent.st_uid == getuid(),
              openedParent.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              openedParent.st_mode & mode_t(0o022) == 0 else { throw ArchiveError.unsafe }
        guard fstatat(parentFD, destination.lastPathComponent, &st, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else { throw ArchiveError.unsafe }
        let stage = try Self.stage(directory: directory, entries: entries, contents: patched,
                                   parentFD: parentFD, parentPath: parent.path)
        defer { stage.cleanup() }
        guard try MindNodeImporter.load(stage.payloadURL) == editedRoots else { throw ArchiveError.unsafe }
        let staged = try Self.capture(stage.payloadURL, parentFD: stage.fd)
        let expected = entries.map { Entry(path: $0.path,
            data: $0.path == (directory ? "contents.xml" : "") ? patched : $0.data) }
        guard staged.directory == directory, staged.entries.count == expected.count,
              zip(staged.entries, expected).allSatisfy({ $0.path == $1.path && $0.data == $1.data }) else {
            throw ArchiveError.unsafe
        }
        guard renameatx_np(stage.fd, "payload.mindnode", parentFD,
                           destination.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw ArchiveError.unsafe }
        stage.published = true
    }
}
