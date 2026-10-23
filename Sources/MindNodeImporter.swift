import Foundation
import CoreFoundation

enum ImportError: LocalizedError {
    case unsupported, zipArchive, missingContents, invalid, tooLarge

    var errorDescription: String? {
        switch self {
        case .unsupported: "Only MindNode v9 binary-plist files or directory packages can be imported read-only; newer or unknown formats are unsupported."
        case .zipArchive: "ZIP-archived MindNode files are unsupported; no archive is extracted."
        case .missingContents: "This MindNode package needs a readable, regular contents.xml file. The source was not changed."
        case .invalid: "The MindNode document has missing data or uses a structure this v9 importer cannot read. The source was not changed."
        case .tooLarge: "The MindNode document exceeds the 8 MiB import limit."
        }
    }
}

struct MindNodeVisualStyle {
    let rgba: [Double]
    let width: CGFloat
}

enum MindNodeImporter {
    static func load(_ url: URL) throws -> [MapNode] { try loadWithStyles(url).roots }

    static func loadWithStyles(_ url: URL) throws -> (roots: [MapNode], styles: [UUID: MindNodeVisualStyle]) {
        let fm = FileManager.default
        guard url.isFileURL, url.pathExtension.lowercased() == "mindnode",
              let kind = (try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType else {
            throw ImportError.unsupported
        }
        let contents: URL
        switch kind {
        case .typeDirectory: contents = url.appendingPathComponent("contents.xml")
        case .typeRegular: contents = url
        default: throw ImportError.unsupported
        }
        guard let attrs = try? fm.attributesOfItem(atPath: contents.path),
              attrs[.type] as? FileAttributeType == .typeRegular else {
            throw kind == .typeDirectory ? ImportError.missingContents : .invalid
        }
        let limit = 8 * 1024 * 1024
        guard let size = attrs[.size] as? NSNumber, size.uint64Value <= UInt64(limit) else {
            throw ImportError.tooLarge
        }
        let data = try Data(contentsOf: contents, options: .mappedIfSafe)
        guard data.count <= limit else { throw ImportError.tooLarge }
        if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) ||
           data.starts(with: [0x50, 0x4b, 0x05, 0x06]) ||
           data.starts(with: [0x50, 0x4b, 0x07, 0x08]) { throw ImportError.zipArchive }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
              format == .binary, let root = plist as? [String: Any],
              let version = root["version"] as? NSNumber,
              CFGetTypeID(version) == CFNumberGetTypeID(),
              !["f", "d"].contains(String(cString: version.objCType)), version.intValue == 9 else {
            throw ImportError.unsupported
        }
        guard let canvas = root["canvas"] as? [String: Any],
              let maps = canvas["mindMaps"] as? [[String: Any]] else {
            throw ImportError.invalid
        }
        var seen = Set<UUID>()
        var styles: [UUID: MindNodeVisualStyle] = [:]
        var count = 0
        func parse(_ value: Any, depth: Int) throws -> MapNode {
            guard depth <= 200, count < 10_000, let node = value as? [String: Any],
                  let rawID = node["nodeID"] as? String, let id = UUID(uuidString: rawID),
                  seen.insert(id).inserted, let title = node["title"] as? [String: Any],
                  let richText = title["text"] as? String,
                  let subnodes = node["subnodes"] as? [Any],
                  let foldNumber = node["hasFoldedSubnodes"] as? NSNumber,
                  CFGetTypeID(foldNumber) == CFBooleanGetTypeID() else {
                throw ImportError.invalid
            }
            count += 1
            if let path = node["pathStyle"] as? [String: Any],
               let stroke = path["strokeStyle"] as? [String: Any],
               let raw = stroke["color"] as? String,
               let width = stroke["width"] as? NSNumber,
               CFGetTypeID(width) == CFNumberGetTypeID(), (0.5...16).contains(width.doubleValue) {
                let channels = raw.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                    .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if channels.count == 4, channels.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                    styles[id] = MindNodeVisualStyle(rgba: channels, width: CGFloat(width.doubleValue))
                }
            }
            let plain = try plainTitle(richText)
            let children = try subnodes.map { try parse($0, depth: depth + 1) }
            return MapNode(id: id, title: plain, children: children, folded: foldNumber.boolValue)
        }
        let roots = try maps.map { map in
            guard let main = map["mainNode"] else { throw ImportError.invalid }
            return try parse(main, depth: 0)
        }
        return (roots, styles)
    }

    static func plainTitle(_ rich: String) throws -> String {
        if rich.isEmpty { return "" } // Real v9 packages use an empty string for untitled nodes.
        // ponytail: title text and path strokes only; decode full typography/attachments after verified samples.
        guard rich.utf8.count <= 65_536,
              rich.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              rich.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw ImportError.invalid
        }
        let handler = PlainTitle()
        let parser = XMLParser(data: Data(rich.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = handler
        guard parser.parse(), handler.valid, handler.depth == 0, handler.hasRoot else {
            throw ImportError.invalid
        }
        return handler.value
    }
}

private final class PlainTitle: NSObject, XMLParserDelegate {
    var value = ""
    var depth = 0
    var hasRoot = false
    var valid = true
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard depth < 64 else { valid = false; parser.abortParsing(); return }
        if depth == 0 { hasRoot = true; if elementName != "p" { valid = false } }
        if !["p", "b", "strong", "i", "em", "u", "span", "br"].contains(elementName) { valid = false }
        if elementName == "br" { value += "\n" }
        depth += 1
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        depth -= 1
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { value += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { valid = false }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        valid = false
        return nil
    }
}
