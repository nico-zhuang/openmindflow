import Foundation
import Darwin

private let ownJSONLimit = MapModel.maxSavedJSONBytes

struct OwnMapDocument: Codable {
    var roots: [MapNode]
    var relationships: [MapRelationship]
    var theme: String?
    var canvasColor: String?

    init(roots: [MapNode], relationships: [MapRelationship] = [],
         theme: String? = nil, canvasColor: String? = nil) {
        self.roots = roots
        self.relationships = relationships
        self.theme = theme
        self.canvasColor = canvasColor
    }

    private enum CodingKeys: String, CodingKey { case version, roots, relationships, theme, canvasColor }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard try fields.decode(Int.self, forKey: .version) == 1 else { throw OwnJSONError.unsupportedVersion }
        roots = try fields.decode([MapNode].self, forKey: .roots)
        relationships = try fields.decode([MapRelationship].self, forKey: .relationships)
        theme = try fields.decodeIfPresent(String.self, forKey: .theme)
        canvasColor = try fields.decodeIfPresent(String.self, forKey: .canvasColor)
    }
    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(1, forKey: .version)
        try fields.encode(roots, forKey: .roots)
        try fields.encode(relationships, forKey: .relationships)
        try fields.encodeIfPresent(theme, forKey: .theme)
        try fields.encodeIfPresent(canvasColor, forKey: .canvasColor)
    }
}

enum OwnJSONError: LocalizedError {
    case invalidPath, invalidFile, tooLarge, duplicateID, invalidWidth, invalidLocation, invalidFont, invalidStyle, invalidImageSize
    case invalidRelationship, duplicateRelationship, unsupportedVersion, requiresDocumentAPI, invalidVideoSize
    case invalidNote, invalidAppearance

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
        case .invalidRelationship: return "A relationship has a missing endpoint, self-loop, or invalid control point."
        case .duplicateRelationship: return "The document contains duplicate relationship IDs."
        case .unsupportedVersion: return "This map document version is not supported."
        case .requiresDocumentAPI: return "This document has relationships or appearance settings; use the complete document API."
        case .invalidNote: return "A note must be at most 64 KiB of UTF-8 text."
        case .invalidAppearance: return "A root shape, fill color, theme, or canvas color is invalid."
        case .invalidVideoSize: return "A video display width must be 60 to 1000 points, require a video, and not share a node with an image."
        }
    }
}

private func checkOwnJSONPath(_ url: URL) throws {
    guard url.isFileURL, url.lastPathComponent.hasSuffix(".mindmap.json"),
          !url.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents.contains(where: {
              $0.lowercased().hasSuffix(".mindnode")
          }) else { throw OwnJSONError.invalidPath }
}

func checkOwnJSONNodes(_ roots: [MapNode]) throws -> Set<UUID> {
    var ids = Set<UUID>()
    func visit(_ nodes: [MapNode], root: Bool) throws {
        for node in nodes {
            guard ids.insert(node.id).inserted else { throw OwnJSONError.duplicateID }
            if let note = node.note, note.utf8.count > 65_536 { throw OwnJSONError.invalidNote }
            if let shape = node.rootShape, (!root || !["rectangle", "rounded"].contains(shape)) {
                throw OwnJSONError.invalidAppearance
            }
            if let fill = node.rootFillColor, (!root || !MapNode.validColor(fill)) {
                throw OwnJSONError.invalidAppearance
            }
            if let width = node.width {
                guard MapNode.validWidth(width) else { throw OwnJSONError.invalidWidth }
            }
            if let width = node.imageWidth,
               (node.image == nil || !width.isFinite || !(60...1000).contains(width)) {
                throw OwnJSONError.invalidImageSize
            }
            if node.image != nil && node.video != nil { throw OwnJSONError.invalidVideoSize }
            if let width = node.videoWidth,
               (node.video == nil || !width.isFinite || !(60...1000).contains(width)) {
                throw OwnJSONError.invalidVideoSize
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
            try visit(node.children, root: false)
        }
    }
    try visit(roots, root: true)
    return ids
}

private func checkOwnDocument(_ document: OwnMapDocument) throws {
    guard document.theme.map({ InspectorTheme(rawValue: $0) != nil }) ?? true,
          document.canvasColor.map(MapNode.validColor) ?? true else { throw OwnJSONError.invalidAppearance }
    let ids = try checkOwnJSONNodes(document.roots)
    var edgeIDs = Set<UUID>()
    for edge in document.relationships {
        guard edgeIDs.insert(edge.id).inserted else { throw OwnJSONError.duplicateRelationship }
        guard validRelationship(edge, nodeIDs: ids) else { throw OwnJSONError.invalidRelationship }
    }
}

func readOwnDocument(_ url: URL) throws -> OwnMapDocument {
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
    let document: OwnMapDocument
    if data.first(where: { ![9, 10, 13, 32].contains($0) }) == UInt8(ascii: "[") {
        document = OwnMapDocument(roots: try JSONDecoder().decode([MapNode].self, from: data))
    } else {
        document = try JSONDecoder().decode(OwnMapDocument.self, from: data)
    }
    try checkOwnDocument(document)
    return document
}

func readOwnJSON(_ url: URL) throws -> [MapNode] {
    let document = try readOwnDocument(url)
    guard document.relationships.isEmpty, document.theme == nil, document.canvasColor == nil else {
        throw OwnJSONError.requiresDocumentAPI
    }
    return document.roots
}

func writeOwnDocument(_ document: OwnMapDocument, to url: URL) throws {
    try checkOwnJSONPath(url)
    try checkOwnDocument(document)
    let data = try document.relationships.isEmpty && document.theme == nil && document.canvasColor == nil
        ? JSONEncoder().encode(document.roots) : JSONEncoder().encode(document)
    guard data.count <= ownJSONLimit else { throw OwnJSONError.tooLarge }
    var info = stat()
    if lstat(url.path, &info) == 0 {
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw OwnJSONError.invalidFile }
    } else if errno != ENOENT {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try data.write(to: url, options: .atomic)
}

func writeOwnJSON(_ roots: [MapNode], to url: URL) throws {
    try checkOwnJSONPath(url)
    var info = stat()
    if lstat(url.path, &info) == 0 {
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw OwnJSONError.invalidFile }
        let existing = try readOwnDocument(url)
        guard existing.relationships.isEmpty, existing.theme == nil, existing.canvasColor == nil else {
            throw OwnJSONError.requiresDocumentAPI
        }
    } else if errno != ENOENT {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try writeOwnDocument(OwnMapDocument(roots: roots), to: url)
}
