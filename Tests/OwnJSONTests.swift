import Foundation
import Darwin

@main
enum OwnJSONTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/own-json-tests-XXXXXX").utf8CString
        let path = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let created = mkdtemp(start) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return String(cString: created)
        }
        let scratch = URL(fileURLWithPath: path, isDirectory: true)
        guard scratch.resolvingSymlinksInPath().standardizedFileURL == scratch.standardizedFileURL,
              scratch.deletingLastPathComponent() == base else { fatalError("Unsafe fixture directory") }
        var info = stat()
        guard lstat(scratch.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { fatalError("Fixture must be owned 0700") }
        defer { try? fm.removeItem(at: scratch) }

        func rejects(_ operation: () throws -> Void) {
            do { try operation(); fatalError("Expected failure") }
            catch { /* An error is the expected result. */ }
        }
        let url = scratch.appendingPathComponent("edited.mindmap.json")
        let unrelated = scratch.appendingPathComponent("unrelated.txt")
        try "leave this alone".write(to: unrelated, atomically: true, encoding: .utf8)
        let root = MapNode(id: UUID(), title: "Before edit", children: (0..<29).map { index in
            MapNode(id: UUID(), title: "Idea \(index) 🌳", children: [], folded: index.isMultiple(of: 2))
        }, folded: false)
        let model = MapModel(roots: [root], selected: root.id)
        try writeOwnJSON(model.roots, to: url)
        model.rename("Edited 🧠\n<&>")
        assert(model.toggleFold())
        let expected = model.roots
        try writeOwnJSON(expected, to: url)
        let reopened = try readOwnJSON(url)
        assert(reopened == expected, "All 30 IDs, titles, order, nesting and fold states survive")
        let sentinel = try String(contentsOf: unrelated, encoding: .utf8)
        assert(sentinel == "leave this alone")

        var active = expected
        let invalid = scratch.appendingPathComponent("invalid.mindmap.json")
        try Data("{not json".utf8).write(to: invalid)
        rejects { active = try readOwnJSON(invalid) }
        assert(active == expected, "A failed open must not replace the active model")
        let afterInvalidOpen = try readOwnJSON(url)
        assert(afterInvalidOpen == expected, "Failed open must not change the saved document")

        let wrong = scratch.appendingPathComponent("other.json")
        rejects { try writeOwnJSON(expected, to: wrong) }
        rejects { _ = try readOwnJSON(wrong) }
        assert(!fm.fileExists(atPath: wrong.path))
        let oversized = scratch.appendingPathComponent("oversized.mindmap.json")
        try Data(count: 8 * 1024 * 1024 + 1).write(to: oversized)
        rejects { _ = try readOwnJSON(oversized) }
        let directory = scratch.appendingPathComponent("directory.mindmap.json", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        rejects { _ = try readOwnJSON(directory) }
        rejects { try writeOwnJSON(expected, to: directory) }
        let linked = scratch.appendingPathComponent("linked.mindmap.json")
        try fm.createSymbolicLink(at: linked, withDestinationURL: url)
        rejects { _ = try readOwnJSON(linked) }
        rejects { try writeOwnJSON(expected, to: linked) }
        let unchanged = try readOwnJSON(url)
        assert(unchanged == expected)
        let giant = [MapNode(id: UUID(), title: String(repeating: "x", count: 8 * 1024 * 1024), children: [], folded: false)]
        rejects { try writeOwnJSON(giant, to: url) }
        let afterOversizedSave = try readOwnJSON(url)
        assert(afterOversizedSave == expected)

        let duplicate = [root, root]
        rejects { try writeOwnJSON(duplicate, to: url) }
        let afterRejectedSave = try readOwnJSON(url)
        assert(afterRejectedSave == expected, "Rejected save must leave previous document intact")
        let duplicatesURL = scratch.appendingPathComponent("duplicates.mindmap.json")
        try JSONEncoder().encode(duplicate).write(to: duplicatesURL)
        rejects { _ = try readOwnJSON(duplicatesURL) }
        let customWidthURL = scratch.appendingPathComponent("custom-width.mindmap.json")
        var resized = root
        resized.width = 136
        try writeOwnJSON([resized], to: customWidthURL)
        let reopenedCustomWidth = try readOwnJSON(customWidthURL)
        assert(reopenedCustomWidth == [resized], "Original-style widths survive Save/Open")
        resized.fontFamily = "STSongti-SC-Regular"
        resized.fontSize = 36
        try writeOwnJSON([resized], to: customWidthURL)
        let reopenedStyled = try readOwnJSON(customWidthURL)
        assert(reopenedStyled == [resized], "Edited original-style font family and size survive separate Save/Open")
        let invalidFontURL = scratch.appendingPathComponent("invalid-font.mindmap.json")
        var invalidFont = resized
        for value in [0.0, 513, -2] {
            invalidFont.fontSize = value
            try JSONEncoder().encode([invalidFont]).write(to: invalidFontURL)
            rejects { _ = try readOwnJSON(invalidFontURL) }
            rejects { try writeOwnJSON([invalidFont], to: url) }
        }
        invalidFont.fontSize = 36
        invalidFont.fontFamily = String(repeating: "x", count: 129)
        try JSONEncoder().encode([invalidFont]).write(to: invalidFontURL)
        rejects { _ = try readOwnJSON(invalidFontURL) }
        rejects { try writeOwnJSON([invalidFont], to: url) }
        let invalidWidthURL = scratch.appendingPathComponent("invalid-width.mindmap.json")
        var unsafe = root
        for width: CGFloat in [0, 59, 1001] {
            unsafe.width = width
            try JSONEncoder().encode([unsafe]).write(to: invalidWidthURL)
            rejects { _ = try readOwnJSON(invalidWidthURL) }
            rejects { try writeOwnJSON([unsafe], to: url) }
        }
        let afterBadWidth = try readOwnJSON(url)
        assert(afterBadWidth == expected, "Invalid width must not replace the saved document")
        let invalidLocationURL = scratch.appendingPathComponent("invalid-location.mindmap.json")
        var placedTooFar = root
        placedTooFar.location = SIMD2(2_000_000, 0)
        try JSONEncoder().encode([placedTooFar]).write(to: invalidLocationURL)
        rejects { _ = try readOwnJSON(invalidLocationURL) }
        rejects { try writeOwnJSON([placedTooFar], to: url) }
        let afterBadLocation = try readOwnJSON(url)
        assert(afterBadLocation == expected, "Invalid source positions cannot replace saved JSON")
        let finalSentinel = try String(contentsOf: unrelated, encoding: .utf8)
        assert(finalSentinel == "leave this alone")
        print("own JSON persistence tests passed")
    }
}
