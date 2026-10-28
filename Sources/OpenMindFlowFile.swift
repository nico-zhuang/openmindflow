import Foundation
import CryptoKit
import Darwin

/// A versioned, bounded binary document. MindNode provenance is opaque to this codec.
enum NativeMapFile {
    struct Payload: Codable {
        var document: OwnMapDocument
        var mindNodeArchive: Data?
        var tabTitle: String? = nil
    }

    static func normalizedTabTitle(_ raw: String) -> String? {
        guard !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !title.isEmpty, title.count <= 128, title.utf8.count <= 255 else { return nil }
        return title
    }

    struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    enum ExpectedDestination: Equatable {
        case absent
        case existing(identity: FileIdentity, digest: Data)
    }

    enum FileError: LocalizedError {
        case invalidPath, invalidFile, tooLarge, invalidHeader, unsupportedVersion, corrupt
        case conflict, durabilityUncertain

        var errorDescription: String? {
            switch self {
            case .invalidPath: return "Choose a safe .mflw file outside a MindNode package."
            case .invalidFile: return "The map document must be a regular file."
            case .tooLarge: return "The map document exceeds the 128 MiB limit."
            case .invalidHeader: return "This is not an OpenMindFlow document."
            case .unsupportedVersion: return "This OpenMindFlow document version is not supported."
            case .corrupt: return "The OpenMindFlow document is incomplete or damaged."
            case .conflict: return "The map document changed on disk; reopen it before saving."
            case .durabilityUncertain: return "The map may have been published, but its directory could not be synced; check the saved file before retrying."
            }
        }
    }

    private static let magic = Data("OMFLW001".utf8)
    private static let headerSize = 48
    private static let maxBytes = 128 * 1024 * 1024

    private static func systemError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    /// Resolve directory components with O_NOFOLLOW, retaining a directory descriptor
    /// for both the final open and atomic rename (rather than re-resolving a path).
    private static func parentDescriptor(for url: URL) throws -> (Int32, String) {
        guard url.isFileURL, url.pathExtension == "mflw",
              url.path == url.standardizedFileURL.path else { throw FileError.invalidPath }
        let components = url.pathComponents
        guard components.first == "/", components.count >= 3,
              !components.dropLast().contains(where: { $0.lowercased().hasSuffix(".mindnode") }) else {
            throw FileError.invalidPath
        }
        // macOS exposes /var and /tmp as system-owned symlinks to /private.
        // Resolve only these known top-level aliases; reject every other linked parent.
        let alias = components[1]
        let systemAlias = alias == "var" || alias == "tmp"
        if systemAlias {
            guard let resolved = realpath("/\(alias)", nil) else { throw FileError.invalidPath }
            defer { free(resolved) }
            guard String(cString: resolved) == "/private/\(alias)" else { throw FileError.invalidPath }
        }
        var directory = open(systemAlias ? "/private" : "/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw systemError() }
        do {
            for name in components.dropFirst().dropLast() {
                let next = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else { throw FileError.invalidPath }
                close(directory)
                directory = next
            }
            return (directory, components.last!)
        } catch {
            close(directory)
            throw error
        }
    }

    static func read(_ url: URL) throws -> Payload {
        try readWithSHA256(url).payload
    }

    /// Retain the two-value API for callers that do not need file identity.
    static func readWithSHA256(_ url: URL) throws -> (payload: Payload, digest: Data) {
        let opened = try readWithFileIdentity(url)
        return (opened.payload, opened.digest)
    }

    /// Decode, hash and identify the same bounded bytes through one no-follow descriptor.
    static func readWithFileIdentity(_ url: URL) throws ->
        (payload: Payload, digest: Data, identity: FileIdentity) {
        let (parent, name) = try parentDescriptor(for: url)
        defer { close(parent) }
        let descriptor = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw systemError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw systemError() }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw FileError.invalidFile }
        guard metadata.st_size <= maxBytes else { throw FileError.tooLarge }
        var bytes = Data()
        while let chunk = try handle.read(upToCount: min(1_048_576, maxBytes + 1 - bytes.count)), !chunk.isEmpty {
            bytes.append(chunk)
            guard bytes.count <= maxBytes else { throw FileError.tooLarge }
        }
        guard bytes.count >= headerSize else { throw FileError.invalidHeader }
        guard bytes.prefix(5) == magic.prefix(5) else { throw FileError.invalidHeader }
        guard bytes.prefix(8) == magic else { throw FileError.unsupportedVersion }
        let length = bytes[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard length <= UInt64(maxBytes - headerSize) else { throw FileError.tooLarge }
        guard length == UInt64(bytes.count - headerSize) else { throw FileError.corrupt }
        let body = bytes.subdata(in: headerSize..<bytes.count)
        guard body.starts(with: Data("bplist00".utf8)),
              Data(SHA256.hash(data: body)) == bytes.subdata(in: 16..<headerSize) else {
            throw FileError.corrupt
        }
        let payload = try PropertyListDecoder().decode(Payload.self, from: body)
        guard payload.tabTitle.map({ normalizedTabTitle($0) == $0 }) ?? true else { throw FileError.corrupt }
        try checkOwnDocument(payload.document)
        let identity = FileIdentity(device: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino))
        return (payload, Data(SHA256.hash(data: bytes)), identity)
    }

    private struct CurrentFile {
        let device: dev_t
        let inode: ino_t
        let digest: Data
    }

    /// Hash a bounded, no-follow descriptor, checking its identity on both sides of the read.
    /// This is cooperative change detection, not an atomic compare-and-swap against another writer.
    private static func currentFile(parent: Int32, name: String) throws -> CurrentFile? {
        var entry = stat()
        if fstatat(parent, name, &entry, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return nil }
            throw systemError()
        }
        guard entry.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw FileError.invalidFile }
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if fd < 0 {
            if errno == ENOENT { throw FileError.conflict }
            throw systemError()
        }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0 else { throw systemError() }
        guard before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw FileError.invalidFile }
        guard before.st_dev == entry.st_dev, before.st_ino == entry.st_ino else { throw FileError.conflict }
        guard before.st_size <= maxBytes else { throw FileError.tooLarge }
        var hash = SHA256()
        var count = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let length = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            if length < 0 {
                if errno == EINTR { continue }
                throw systemError()
            }
            if length == 0 { break }
            count += length
            guard count <= maxBytes else { throw FileError.tooLarge }
            hash.update(data: Data(buffer.prefix(length)))
        }
        var after = stat()
        var pathEntry = stat()
        guard fstat(fd, &after) == 0,
              fstatat(parent, name, &pathEntry, AT_SYMLINK_NOFOLLOW) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              after.st_dev == pathEntry.st_dev, after.st_ino == pathEntry.st_ino else {
            throw FileError.conflict
        }
        return CurrentFile(device: after.st_dev, inode: after.st_ino, digest: Data(hash.finalize()))
    }

    /// Check a caller's last-seen digest without decoding the document.
    static func verifyExpectedCurrent(_ url: URL, expectedCurrentSHA256: Data) throws {
        let (parent, name) = try parentDescriptor(for: url)
        defer { close(parent) }
        guard let current = try currentFile(parent: parent, name: name),
              current.digest == expectedCurrentSHA256 else { throw FileError.conflict }
    }

    /// Capture the destination through the same descriptor-relative identity and bounded hash
    /// that the writer observes before staging. Missing is distinct from an uncertain entry.
    static func destinationSnapshot(_ url: URL) throws -> ExpectedDestination {
        let (parent, name) = try parentDescriptor(for: url)
        defer { close(parent) }
        guard let current = try currentFile(parent: parent, name: name) else { return .absent }
        return .existing(identity: FileIdentity(device: UInt64(current.device), inode: UInt64(current.inode)),
                         digest: current.digest)
    }

    /// A nil digest and nil expectedDestination preserve the original save API.
    static func write(_ payload: Payload, to url: URL, expectedCurrentSHA256: Data? = nil,
                      expectedDestination: ExpectedDestination? = nil) throws {
        let (parent, name) = try parentDescriptor(for: url)
        defer { close(parent) }
        try checkOwnDocument(payload.document)
        guard payload.tabTitle.map({ normalizedTabTitle($0) == $0 }) ?? true else { throw FileError.corrupt }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let body = try encoder.encode(payload)
        guard body.count <= maxBytes - headerSize else { throw FileError.tooLarge }
        guard body.starts(with: Data("bplist00".utf8)) else { throw FileError.corrupt }
        let lastSeen = try currentFile(parent: parent, name: name)
        if let expectedDestination {
            let observed: ExpectedDestination = lastSeen.map {
                .existing(identity: FileIdentity(device: UInt64($0.device), inode: UInt64($0.inode)), digest: $0.digest)
            } ?? .absent
            guard observed == expectedDestination else { throw FileError.conflict }
        }
        if let expectedCurrentSHA256, lastSeen?.digest != expectedCurrentSHA256 {
            throw FileError.conflict
        }
        var bytes = magic
        var length = UInt64(body.count).bigEndian
        withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: SHA256.hash(data: body))
        bytes.append(body)

        // The source of publication is held by an owned directory descriptor, never
        // looked up by a swappable filename in a shared-writable parent.
        let stagingName = ".openmindflow-\(UUID().uuidString)"
        guard mkdirat(parent, stagingName, 0o700) == 0 else { throw systemError() }
        let stage = openat(parent, stagingName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard stage >= 0 else {
            // Do not remove an unverified pathname if opening it failed.
            throw systemError()
        }
        var stageInfo = stat()
        guard fstat(stage, &stageInfo) == 0, stageInfo.st_uid == getuid(),
              stageInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            close(stage)
            throw FileError.invalidPath
        }
        var tempInfo: stat? = nil
        defer {
            // Only clean our own objects. A renamed/replaced staging directory is
            // deliberately left untouched rather than deleting somebody else's entry.
            var onDisk = stat()
            if let tempInfo,
               fstatat(stage, "payload", &onDisk, AT_SYMLINK_NOFOLLOW) == 0,
               onDisk.st_uid == getuid(), onDisk.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
               onDisk.st_dev == tempInfo.st_dev, onDisk.st_ino == tempInfo.st_ino {
                _ = unlinkat(stage, "payload", 0)
            }
            var namedStage = stat()
            if fstatat(parent, stagingName, &namedStage, AT_SYMLINK_NOFOLLOW) == 0,
               namedStage.st_dev == stageInfo.st_dev, namedStage.st_ino == stageInfo.st_ino,
               namedStage.st_uid == getuid(), namedStage.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                _ = unlinkat(parent, stagingName, AT_REMOVEDIR)
            }
            close(stage)
        }
        let descriptor = openat(stage, "payload", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw systemError() }
        var created = stat()
        guard fstat(descriptor, &created) == 0, created.st_uid == getuid(),
              created.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            close(descriptor)
            throw FileError.invalidFile
        }
        tempInfo = created
        do {
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            try handle.write(contentsOf: bytes)
            guard fsync(descriptor) == 0 else { throw systemError() }
        } catch {
            close(descriptor)
            throw error
        }
        close(descriptor)
        let latest = try currentFile(parent: parent, name: name)
        if let lastSeen {
            guard let latest, latest.device == lastSeen.device, latest.inode == lastSeen.inode,
                  latest.digest == lastSeen.digest else { throw FileError.conflict }
            guard renameat(stage, "payload", parent, name) == 0 else { throw systemError() }
        } else {
            // The no-overwrite condition must be enforced by the kernel at publication.
            guard latest == nil else { throw FileError.conflict }
            if renameatx_np(stage, "payload", parent, name, UInt32(RENAME_EXCL)) != 0 {
                if errno == EEXIST { throw FileError.conflict }
                throw systemError()
            }
        }
        // Publication already happened. A failed directory fsync means durability is
        // unknown: callers must inspect the destination rather than blindly retry.
        guard fsync(parent) == 0 else { throw FileError.durabilityUncertain }
    }
}
