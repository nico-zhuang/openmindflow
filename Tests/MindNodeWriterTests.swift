import AppKit
import Darwin

@main
enum MindNodeWriterTests {
    static func main() throws {
        _ = NSApplication.shared // Offscreen only.
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/mindnode-writer-tests-XXXXXX").utf8CString
        let path = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let created = mkdtemp(start) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return String(cString: created)
        }
        let scratch = URL(fileURLWithPath: path, isDirectory: true)
        var info = stat()
        guard scratch.deletingLastPathComponent() == base,
              scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
              lstat(scratch.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Unsafe synthetic fixture") }
        let fixtureInode = info.st_ino
        defer {
            var current = stat()
            if lstat(scratch.path, &current) == 0, current.st_ino == fixtureInode,
               current.st_uid == getuid(), current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
               scratch.deletingLastPathComponent() == base,
               scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL {
                try? fm.removeItem(at: scratch)
            }
        }

        var child = MapNode(id: UUID(), title: "子节点 & <tag> 🧭\nNext", children: [], folded: true)
        child.location = SIMD2(320.5, -120.25)
        child.width = 260
        child.fontFamily = "Helvetica"
        child.fontSize = 18
        child.textAlignment = "center"
        child.branchStrokeColor = "#336699FF"
        child.branchStrokeWidth = 4
        let root = MapNode(id: UUID(), title: "Synthetic root", children: [child], folded: false)
        let roots = [root]
        let output = scratch.appendingPathComponent("created.mindnode", isDirectory: true)
        try MindNodeWriter.write(roots, to: output, relationships: [])
        let detailed = try MindNodeImporter.loadDetailed(output)
        assert(detailed.roots[0].id == root.id && detailed.roots[0].title == root.title)
        let reopened = detailed.roots[0].children[0]
        assert(reopened.id == child.id && reopened.title == child.title && reopened.folded)
        assert(reopened.location == child.location && reopened.width == child.width)
        assert(reopened.fontFamily == child.fontFamily && reopened.fontSize == child.fontSize)
        assert(detailed.presentation[child.id]?.font?.alignment == "center")
        assert(detailed.styles[child.id]?.width == 4)
        assert(detailed.styles[child.id]?.rgba == [0x33 / 255.0, 0x66 / 255.0, 0x99 / 255.0, 1])
        let payload = output.appendingPathComponent("contents.xml")
        let before = try Data(contentsOf: payload)
        do { try MindNodeWriter.write(roots, to: output, relationships: []); fatalError("Overwrote existing package") }
        catch MindNodeWriter.WriterError.destinationExists { }
        assert((try? Data(contentsOf: payload)) == before)

        var unimported = detailed
        unimported.hasUnimportedConnections = true
        let omittedConnection = scratch.appendingPathComponent("omitted-connection.mindnode")
        do { try MindNodeWriter.write(roots, to: omittedConnection, imported: unimported, relationships: [])
             fatalError("Silently lost original import connections") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: omittedConnection.path))
        unimported.hasUnimportedConnections = false
        unimported.hasUnimportedAttachments = true
        let omittedMedia = scratch.appendingPathComponent("omitted-original-media.mindnode")
        do { try MindNodeWriter.write(roots, to: omittedMedia, imported: unimported, relationships: [])
             fatalError("Silently lost original import attachments") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: omittedMedia.path))
        unimported.hasUnimportedAttachments = false
        unimported.hasUnimportedRichTitles = true
        let omittedRichTitle = scratch.appendingPathComponent("omitted-rich-title.mindnode")
        do { try MindNodeWriter.write(roots, to: omittedRichTitle, imported: unimported, relationships: [])
             fatalError("Silently lost original bold/italic rich-text styling") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: omittedRichTitle.path))
        unimported.hasUnimportedRichTitles = false
        unimported.hasUnimportedTheme = true
        let unreadableTheme = scratch.appendingPathComponent("unreadable-theme.mindnode")
        do { try MindNodeWriter.write(roots, to: unreadableTheme, imported: unimported, relationships: [])
             fatalError("Silently omitted unreadable original theme package") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: unreadableTheme.path))
        let importedCopy = scratch.appendingPathComponent("imported-copy.mindnode", isDirectory: true)
        try MindNodeWriter.write(detailed.roots, to: importedCopy, imported: detailed, relationships: [])
        let copied = try MindNodeImporter.loadDetailed(importedCopy)
        assert(copied.roots == detailed.roots)
        assert(copied.styles[child.id]?.rgba == detailed.styles[child.id]?.rgba)
        assert((try? Data(contentsOf: payload)) == before)
        var edited = detailed.roots
        edited[0].children[0].title = "Edited after import"
        edited[0].children[0].location = SIMD2(580, 125)
        edited[0].children[0].width = 310
        edited[0].children[0].fontSize = 22
        edited[0].children[0].textAlignment = "right"
        edited[0].children[0].branchStrokeColor = "#FF0000FF"
        edited[0].children[0].branchStrokeWidth = 5
        let editedOutput = scratch.appendingPathComponent("edited-import.mindnode")
        try MindNodeWriter.write(edited, to: editedOutput, imported: detailed, relationships: [])
        let editedAgain = try MindNodeImporter.loadDetailed(editedOutput)
        assert(editedAgain.roots[0].children[0].title == "Edited after import")
        assert(editedAgain.roots[0].children[0].location == SIMD2(580, 125))
        assert(editedAgain.roots[0].children[0].width == 310)
        assert(editedAgain.roots[0].children[0].fontSize == 22)
        assert(editedAgain.presentation[child.id]?.font?.alignment == "right")
        assert(editedAgain.styles[child.id]?.rgba == [1, 0, 0, 1] && editedAgain.styles[child.id]?.width == 5)
        assert((try? Data(contentsOf: payload)) == before)
        let theme = MindNodeThemeMetadata(identifier: UUID(), backgroundColor: [1, 1, 1, 1],
            allowNodeStrokeColorVariation: nil, baseSubnode: nil, mainNodes: [], subnodeLevels: [])
        let themed = MindNodeDetailedImport(roots: roots, styles: [:], presentation: [:], theme: theme)
        let themedOutput = scratch.appendingPathComponent("theme.mindnode")
        do { try MindNodeWriter.write(roots, to: themedOutput, imported: themed, relationships: []); fatalError("Silently lost theme") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: themedOutput.path))

        var unsupported = child
        unsupported.strokeStyle = "dashed" // No verified v9 line-dash schema or importer roundtrip.
        let dashed = scratch.appendingPathComponent("dashed.mindnode")
        do { try MindNodeWriter.write([unsupported], to: dashed, relationships: []); fatalError("Silently lost line dash") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: dashed.path))
        unsupported = child
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 12,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 12, height: 12).fill()
        NSGraphicsContext.restoreGraphicsState()
        unsupported.image = try MapImage(data: bitmap.representation(using: .png, properties: [:])!)
        unsupported.imageWidth = 160 // Unsupported media must never disappear silently.
        let media = scratch.appendingPathComponent("media.mindnode")
        do { try MindNodeWriter.write([unsupported], to: media, relationships: []); fatalError("Silently lost image property") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: media.path))
        unsupported = child
        unsupported.videoWidth = 220 // This field is not represented in verified v9 export yet.
        let video = scratch.appendingPathComponent("video.mindnode")
        do { try MindNodeWriter.write([unsupported], to: video, relationships: []); fatalError("Silently lost video size") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: video.path))
        let relations = scratch.appendingPathComponent("relations.mindnode")
        let edge = MapRelationship(from: root.id, to: child.id)
        do { try MindNodeWriter.write(roots, to: relations, relationships: [edge]); fatalError("Silently lost relationship") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: relations.path))
        let duplicates = scratch.appendingPathComponent("duplicate.mindnode")
        do { try MindNodeWriter.write([root, root], to: duplicates, relationships: []); fatalError("Duplicate UUID accepted") }
        catch MindNodeWriter.WriterError.unsupported { }
        assert(!fm.fileExists(atPath: duplicates.path))
        let existingFile = scratch.appendingPathComponent("occupied.mindnode")
        let sentinel = Data("untouched synthetic file".utf8)
        try sentinel.write(to: existingFile)
        do { try MindNodeWriter.write(roots, to: existingFile, relationships: []); fatalError("Overwrote existing file") }
        catch MindNodeWriter.WriterError.destinationExists { }
        assert((try? Data(contentsOf: existingFile)) == sentinel)
        let linked = scratch.appendingPathComponent("alias.mindnode")
        try fm.createSymbolicLink(at: linked, withDestinationURL: output)
        do { try MindNodeWriter.write(roots, to: linked, relationships: []); fatalError("Overwrote symlink") }
        catch MindNodeWriter.WriterError.destinationExists { }
        let wrong = scratch.appendingPathComponent("wrong.json")
        do { try MindNodeWriter.write(roots, to: wrong, relationships: []); fatalError("Wrong suffix accepted") }
        catch MindNodeWriter.WriterError.invalidDestination { }
        let nested = output.appendingPathComponent("inside.mindnode")
        do { try MindNodeWriter.write(roots, to: nested, relationships: []); fatalError("Wrote into source package") }
        catch MindNodeWriter.WriterError.invalidDestination { }
        let aliasParent = scratch.appendingPathComponent("source-alias")
        try fm.createSymbolicLink(at: aliasParent, withDestinationURL: output)
        do { try MindNodeWriter.write(roots, to: aliasParent.appendingPathComponent("inside.mindnode"), relationships: []); fatalError("Followed source symlink") }
        catch MindNodeWriter.WriterError.invalidDestination { }
        assert(!fm.fileExists(atPath: nested.path))
        assert((try? Data(contentsOf: payload)) == before)
        let entries = try fm.contentsOfDirectory(atPath: scratch.path)
        assert(!entries.contains { $0.hasPrefix(".mindnode-writer-") })
        print("synthetic v9 writer creation, imported copy, no-overwrite and unsupported-media tests passed")
    }
}
