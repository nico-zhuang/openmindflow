import AppKit
import Darwin
import CryptoKit

@main
enum OpenMindFlowFileTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var template = (base.path + "/openmindflow-codec-XXXXXX").utf8CString
        let scratch = try template.withUnsafeMutableBufferPointer { bytes -> URL in
            guard let pointer = bytes.baseAddress, let result = mkdtemp(pointer) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return URL(fileURLWithPath: String(cString: result), isDirectory: true)
        }
        var info = stat()
        guard scratch.deletingLastPathComponent() == base,
              scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
              lstat(scratch.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Unsafe fixture") }
        let ownedInode = info.st_ino
        defer {
            var current = stat()
            if lstat(scratch.path, &current) == 0, current.st_ino == ownedInode,
               current.st_uid == getuid(), current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
               scratch.deletingLastPathComponent() == base,
               scratch.resolvingSymlinksInPath().standardizedFileURL == scratch {
                try? fm.removeItem(at: scratch)
            }
        }

        func rejects(_ name: String, _ operation: () throws -> Void) {
            do { try operation(); fatalError("Expected rejection: \(name)") }
            catch { }
        }
        let file = scratch.appendingPathComponent("test.mflw")
        let a = UUID(), b = UUID()
        var first = MapNode(id: a, title: "A", children: [MapNode(id: b, title: "B", children: [], folded: true)], folded: false)
        first.note = "Notes and media survive"
        first.rootShape = "rounded"
        first.rootFillColor = "#112233FF"
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        first.image = try MapImage(data: bitmap.representation(using: .png, properties: [:])!)
        let document = OwnMapDocument(roots: [first], relationships: [MapRelationship(from: a, to: b)],
                                      theme: "tropical", canvasColor: "#102030FF")
        let provenance = Data([0, 255, 32, 1, 0, 254])
        try NativeMapFile.write(.init(document: document, mindNodeArchive: provenance), to: file)
        let bytes = try Data(contentsOf: file)
        assert(bytes.starts(with: Data("OMFLW001".utf8)))
        assert(bytes.first != UInt8(ascii: "{") && bytes.first != UInt8(ascii: "["))
        assert(bytes.subdata(in: 48..<56) == Data("bplist00".utf8))
        let reopened = try NativeMapFile.read(file)
        assert(reopened.document.roots == document.roots)
        assert(reopened.document.relationships == document.relationships)
        assert(reopened.document.theme == document.theme && reopened.document.canvasColor == document.canvasColor)
        assert(reopened.mindNodeArchive == provenance)
        let (snapshot, snapshotDigest) = try NativeMapFile.readWithSHA256(file)
        assert(snapshot.document.roots == document.roots && snapshot.mindNodeArchive == provenance)
        assert(snapshotDigest == Data(SHA256.hash(data: bytes)), "Read digest covers the entire original file")

        func badFile(_ name: String, _ contents: Data) throws {
            let url = scratch.appendingPathComponent("\(name).mflw")
            try contents.write(to: url)
            rejects(name) { _ = try NativeMapFile.read(url) }
            rejects("\(name) snapshot") { _ = try NativeMapFile.readWithSHA256(url) }
        }
        for end in [0, 3, 8, 12, 16, 47, 48, bytes.count - 1] {
            try badFile("truncated-\(end)", Data(bytes.prefix(end)))
        }
        var corrupted = bytes
        corrupted[48] ^= 1
        try badFile("corrupted", corrupted)
        var wrongVersion = bytes
        wrongVersion[7] = UInt8(ascii: "2")
        try badFile("version", wrongVersion)
        var wrongLength = bytes
        wrongLength[15] ^= 1
        try badFile("length", wrongLength)
        try badFile("json", try JSONEncoder().encode(document))
        try badFile("json-array", Data("[]".utf8))
        let tooLarge = scratch.appendingPathComponent("oversized.mflw")
        let fd = open(tooLarge.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard ftruncate(fd, 128 * 1024 * 1024 + 1) == 0 else { close(fd); fatalError("Unable to create sparse oversized fixture") }
        close(fd)
        rejects("size cap") { _ = try NativeMapFile.read(tooLarge) }
        rejects("wrong extension") { try NativeMapFile.write(.init(document: document, mindNodeArchive: nil), to: scratch.appendingPathComponent("bad.json")) }
        let linked = scratch.appendingPathComponent("linked.mflw")
        try fm.createSymbolicLink(at: linked, withDestinationURL: file)
        rejects("linked read") { _ = try NativeMapFile.read(linked) }
        rejects("linked snapshot read") { _ = try NativeMapFile.readWithSHA256(linked) }
        rejects("linked destination") { try NativeMapFile.write(.init(document: document, mindNodeArchive: nil), to: linked) }
        let package = scratch.appendingPathComponent("source.mindnode", isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: false)
        rejects("package write") { try NativeMapFile.write(.init(document: document, mindNodeArchive: nil), to: package.appendingPathComponent("nested.mflw")) }
        rejects("package read") { _ = try NativeMapFile.read(package.appendingPathComponent("nested.mflw")) }
        let alias = scratch.appendingPathComponent("package-alias", isDirectory: true)
        try fm.createSymbolicLink(at: alias, withDestinationURL: package)
        rejects("symlinked parent") { try NativeMapFile.write(.init(document: document, mindNodeArchive: nil), to: alias.appendingPathComponent("nested.mflw")) }
        var invalid = document
        invalid.roots.append(first)
        rejects("invalid model") { try NativeMapFile.write(.init(document: invalid, mindNodeArchive: nil), to: file) }
        let unchanged = try Data(contentsOf: file)
        assert(unchanged == bytes, "Rejected writes leave original bytes intact")
        let replacement = Data([9, 8, 7, 6])
        // A caller with the last-seen digest may save only while the on-disk bytes match.
        try NativeMapFile.verifyExpectedCurrent(file, expectedCurrentSHA256: Data(SHA256.hash(data: bytes)))
        let expectedSave = scratch.appendingPathComponent("expected-save.mflw")
        try bytes.write(to: expectedSave)
        let (savedSnapshot, savedDigest) = try NativeMapFile.readWithSHA256(expectedSave)
        assert(savedSnapshot.mindNodeArchive == provenance && savedDigest == snapshotDigest)
        try NativeMapFile.write(.init(document: savedSnapshot.document, mindNodeArchive: replacement), to: expectedSave,
                                expectedCurrentSHA256: savedDigest)
        let expectedSavedPayload = try NativeMapFile.read(expectedSave)
        assert(expectedSavedPayload.mindNodeArchive == replacement)
        do {
            try NativeMapFile.write(.init(document: document, mindNodeArchive: replacement),
                                    to: scratch.appendingPathComponent("missing.mflw"),
                                    expectedCurrentSHA256: Data(SHA256.hash(data: bytes)))
            fatalError("A missing expected destination must conflict")
        } catch NativeMapFile.FileError.conflict { }
        let external = Data("external revision".utf8)
        try external.write(to: file)
        do {
            try NativeMapFile.write(.init(document: snapshot.document, mindNodeArchive: replacement), to: file,
                                    expectedCurrentSHA256: snapshotDigest)
            fatalError("A stale document must not overwrite external changes")
        } catch NativeMapFile.FileError.conflict { }
        let externallyUpdated = try Data(contentsOf: file)
        assert(externallyUpdated == external)
        do {
            try NativeMapFile.verifyExpectedCurrent(file, expectedCurrentSHA256: Data(SHA256.hash(data: bytes)))
            fatalError("An out-of-date digest must be rejected")
        } catch NativeMapFile.FileError.conflict { }
        // Existing write(_:to:) remains a valid explicit save of a regular document.
        try NativeMapFile.write(.init(document: document, mindNodeArchive: replacement), to: file)
        let updated = try NativeMapFile.read(file)
        assert(updated.document.roots == document.roots && updated.mindNodeArchive == replacement)
        let updatedBytes = try Data(contentsOf: file)
        assert(updatedBytes != bytes, "Atomic re-save replaces the whole document")
        let leftovers = try fm.contentsOfDirectory(atPath: scratch.path)
            .filter { $0.hasPrefix(".openmindflow-") }
        assert(leftovers.isEmpty, "Owned staging directories must be removed after saves and conflicts")
        print("native versioned binary codec and safety tests passed")
    }
}
