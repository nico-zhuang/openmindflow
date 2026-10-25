import Foundation
import Darwin

// Synthetic v9 subset only. Reading this with our importer does not prove the original app accepts it.
enum MindNodeWriter {
    enum WriterError: LocalizedError {
        case invalidDestination, destinationExists, unsupported, tooLarge

        var errorDescription: String? {
            switch self {
            case .invalidDestination: "Choose a new .mindnode package outside any existing .mindnode document."
            case .destinationExists: "The destination already exists; no file was replaced."
            case .unsupported: "This map contains a feature whose MindNode v9 format is not verified; no package was written."
            case .tooLarge: "The generated v9 contents exceed the 8 MiB importer limit."
            }
        }
    }

    static func write(_ roots: [MapNode], to destination: URL,
                      imported: MindNodeDetailedImport? = nil,
                      relationships: [MapRelationship]) throws {
        let target = destination.standardizedFileURL
        let parent = target.deletingLastPathComponent()
        guard destination.isFileURL, target.pathExtension.lowercased() == "mindnode",
              parent.resolvingSymlinksInPath().standardizedFileURL == parent,
              !parent.pathComponents.contains(where: { $0.lowercased().hasSuffix(".mindnode") }) else {
            throw WriterError.invalidDestination
        }
        guard imported?.theme == nil,
              imported?.hasUnimportedConnections != true,
              imported?.hasUnimportedAttachments != true,
              imported?.hasUnimportedRichTitles != true,
              imported?.hasUnimportedTheme != true,
              relationships.isEmpty else { throw WriterError.unsupported }
        let parentFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parentFD >= 0 else { throw WriterError.invalidDestination }
        defer { _ = close(parentFD) }
        var info = stat()
        guard fstat(parentFD, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw WriterError.invalidDestination }
        if fstatat(parentFD, target.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            throw WriterError.destinationExists
        }
        guard errno == ENOENT else { throw WriterError.invalidDestination }
        let encoded = try contents(roots, imported: imported)
        guard encoded.count <= 8 * 1024 * 1024 else { throw WriterError.tooLarge }

        var pattern = (parent.path + "/.mindnode-writer-XXXXXX").utf8CString
        let path = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let start = bytes.baseAddress, let created = mkdtemp(start) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return String(cString: created)
        }
        let stage = URL(fileURLWithPath: path, isDirectory: true)
        guard lstat(stage.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o777) == mode_t(0o700) else { throw WriterError.invalidDestination }
        let inode = info.st_ino
        defer {
            var current = stat()
            if stage.deletingLastPathComponent() == parent,
               lstat(stage.path, &current) == 0, current.st_ino == inode,
               current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
               current.st_uid == getuid(),
               stage.resolvingSymlinksInPath().standardizedFileURL == stage {
                try? FileManager.default.removeItem(at: stage)
            }
        }
        let payload = stage.appendingPathComponent("payload.mindnode", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: false)
        try encoded.write(to: payload.appendingPathComponent("contents.xml"), options: .atomic)
        let reopened = try MindNodeImporter.loadDetailed(payload)
        try verify(roots, imported: imported, reopened: reopened)
        guard renameatx_np(parentFD, stage.lastPathComponent + "/payload.mindnode",
                           parentFD, target.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw WriterError.destinationExists }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func contents(_ roots: [MapNode], imported: MindNodeDetailedImport?) throws -> Data {
        var seen = Set<UUID>()
        var count = 0
        func rgba(_ hex: String) throws -> [Double] {
            guard hex.count == 9, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else {
                throw WriterError.unsupported
            }
            return [Double((value >> 24) & 255), Double((value >> 16) & 255),
                    Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
        }
        func tuple(_ values: [Double]) throws -> String {
            guard values.count == 4, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw WriterError.unsupported
            }
            return "{" + values.map { String($0) }.joined(separator: ", ") + "}"
        }
        func render(_ node: MapNode, depth: Int) throws -> [String: Any] {
            guard depth <= 200, count < 10_000, seen.insert(node.id).inserted,
                  node.image == nil, node.imageWidth == nil,
                   node.video == nil, node.videoWidth == nil,
                  node.strokeStyle == nil else { throw WriterError.unsupported }
            count += 1
            let meta = imported?.presentation[node.id]
            guard meta?.font?.alignmentCode == nil, meta?.font?.bold == nil,
                  meta?.font?.italic == nil else { throw WriterError.unsupported }
            let family = node.fontFamily ?? meta?.font?.family
            let size = node.fontSize ?? meta?.font?.pointSize
            let alignment = node.textAlignment ?? meta?.font?.alignment
            if let family {
                guard !family.isEmpty, family.count <= 80,
                      family.unicodeScalars.allSatisfy({ CharacterSet.letters.union(.decimalDigits)
                          .union(CharacterSet(charactersIn: " -_.")).contains($0) }) else {
                    throw WriterError.unsupported
                }
            }
            if let size { guard size.isFinite, (1...512).contains(size) else { throw WriterError.unsupported } }
            if let alignment { guard ["left", "center", "right", "justify"].contains(alignment) else { throw WriterError.unsupported } }
            var css: [String] = []
            if family != nil || size != nil { css.append("font: \(size ?? 20)px \(family ?? "STSongti-SC-Regular")") }
            if let color = meta?.font?.color {
                guard color.count == 4, color.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                    throw WriterError.unsupported
                }
                css.append("color: rgba(\(color[0] * 255), \(color[1] * 255), \(color[2] * 255), \(color[3]))")
            }
            if let alignment { css.append("text-align: \(alignment)") }
            guard node.title.unicodeScalars.allSatisfy({ scalar in
                let value = scalar.value
                return value == 9 || value == 10 || (0x20...0xD7FF).contains(value) ||
                    (0xE000...0xFFFD).contains(value) || (0x10000...0x10FFFF).contains(value)
            }) else { throw WriterError.unsupported }
            let text = node.title.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br/>")
            let rich = node.title.isEmpty ? "" : "<p\(css.isEmpty ? "" : " style=\"" + css.joined(separator: "; ") + "\"")>\(text)</p>"
            guard rich.utf8.count <= 65_536 else { throw WriterError.unsupported }
            var title: [String: Any] = ["text": rich]
            if let width = node.width {
                guard MapNode.validWidth(width) else { throw WriterError.unsupported }
                title["maxWidth"] = Double(width)
                title["allowToShrinkWidth"] = false
            } else if let maxWidth = meta?.maxWidth {
                guard maxWidth.isFinite, (1...100_000).contains(maxWidth) else { throw WriterError.unsupported }
                title["maxWidth"] = maxWidth
                title["allowToShrinkWidth"] = meta?.allowToShrinkWidth ?? true
            }
            var result: [String: Any] = ["nodeID": node.id.uuidString, "title": title,
                                          "subnodes": try node.children.map { try render($0, depth: depth + 1) },
                                          "hasFoldedSubnodes": node.folded]
            if let location = node.location {
                guard location.x.isFinite, location.y.isFinite,
                      abs(location.x) <= 1_000_000, abs(location.y) <= 1_000_000 else { throw WriterError.unsupported }
                result["location"] = "{\(location.x), \(location.y)}"
            } else if let point = meta?.location {
                guard point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000,
                      abs(point.y) <= 1_000_000 else { throw WriterError.unsupported }
                result["location"] = "{\(point.x), \(point.y)}"
            }
            if let fill = meta?.fillColor { result["shapeStyle"] = ["fillColor": try tuple(fill)] }
            if let changed = meta?.styleChangedByUser { result["styleChangedByUser"] = changed }
            let legacy = imported?.styles[node.id]
            if node.branchStrokeColor != nil || node.branchStrokeWidth != nil || legacy != nil {
                let color: [Double] = try node.branchStrokeColor.map { try rgba($0) }
                    ?? legacy?.rgba ?? [0.078, 0.62, 0.757, 1]
                let width = node.branchStrokeWidth ?? legacy?.width ?? 2
                guard width.isFinite, (0.5...16).contains(width) else { throw WriterError.unsupported }
                result["pathStyle"] = ["strokeStyle": ["color": try tuple(color), "width": Double(width)]]
            }
            return result
        }
        let maps = try roots.map { ["mainNode": try render($0, depth: 0)] }
        return try PropertyListSerialization.data(fromPropertyList: ["version": 9, "canvas": ["mindMaps": maps]],
                                                  format: .binary, options: 0)
    }

    private static func verify(_ roots: [MapNode], imported: MindNodeDetailedImport?,
                               reopened: MindNodeDetailedImport) throws {
        func equal(_ expected: MapNode, _ actual: MapNode) -> Bool {
            guard expected.id == actual.id, expected.title == actual.title, expected.folded == actual.folded,
                  expected.width == actual.width, expected.location == actual.location,
                  expected.fontFamily == actual.fontFamily, expected.fontSize == actual.fontSize,
                  expected.children.count == actual.children.count else { return false }
            return zip(expected.children, actual.children).allSatisfy(equal)
        }
        guard roots.count == reopened.roots.count,
              zip(roots, reopened.roots).allSatisfy(equal) else { throw WriterError.unsupported }
        var byID: [UUID: MapNode] = [:]
        for node in roots {
            func check(_ node: MapNode) throws {
                byID[node.id] = node
                let id = node.id, style = reopened.styles[id]
                if let width = node.branchStrokeWidth, style?.width != width { throw WriterError.unsupported }
                if let hex = node.branchStrokeColor {
                    guard let value = UInt32(hex.dropFirst(), radix: 16), hex.first == "#",
                          style?.rgba == [Double((value >> 24) & 255), Double((value >> 16) & 255),
                                          Double((value >> 8) & 255), Double(value & 255)].map({ $0 / 255 }) else {
                        throw WriterError.unsupported
                    }
                }
                if let align = node.textAlignment,
                   reopened.presentation[id]?.font?.alignment != align { throw WriterError.unsupported }
                for child in node.children { try check(child) }
            }
            try check(node)
        }
        if let imported {
            for (id, style) in imported.styles where byID[id] != nil {
                guard let node = byID[id], let copy = reopened.styles[id],
                      copy.rgba == (try node.branchStrokeColor.map { hex -> [Double] in
                          guard let value = UInt32(hex.dropFirst(), radix: 16) else { throw WriterError.unsupported }
                          return [Double((value >> 24) & 255), Double((value >> 16) & 255),
                                  Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
                      } ?? style.rgba),
                      copy.width == (node.branchStrokeWidth ?? style.width) else { throw WriterError.unsupported }
            }
            for (id, meta) in imported.presentation where byID[id] != nil {
                guard let node = byID[id], let copy = reopened.presentation[id],
                      copy.location == (node.location.map({ CGPoint(x: $0.x, y: $0.y) }) ?? meta.location),
                      copy.maxWidth == (node.width.map(Double.init) ?? meta.maxWidth),
                      copy.allowToShrinkWidth == (node.width == nil ? meta.allowToShrinkWidth : false),
                      copy.styleChangedByUser == meta.styleChangedByUser,
                      copy.fillColor == meta.fillColor,
                      copy.font?.family == (node.fontFamily ?? meta.font?.family),
                      copy.font?.pointSize == (node.fontSize ?? meta.font?.pointSize),
                      copy.font?.color == meta.font?.color,
                      copy.font?.alignment == (node.textAlignment ?? meta.font?.alignment) else {
                    throw WriterError.unsupported
                }
            }
        }
    }
}
