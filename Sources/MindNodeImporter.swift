import Foundation
import CoreFoundation

enum ImportError: LocalizedError {
    case unsupported, invalid, tooLarge

    var errorDescription: String? {
        switch self {
        case .unsupported: "Only MindNode v9 directory packages can be imported read-only."
        case .invalid: "The MindNode document is missing or malformed."
        case .tooLarge: "The MindNode document exceeds the 8 MiB import limit."
        }
    }
}

enum MindNodeImporter {
    static func load(_ url: URL) throws -> [MapNode] {
        let fm = FileManager.default
        guard url.isFileURL, url.pathExtension.lowercased() == "mindnode",
              (try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeDirectory else {
            throw ImportError.unsupported
        }
        let contents = url.appendingPathComponent("contents.xml")
        guard let attrs = try? fm.attributesOfItem(atPath: contents.path),
              attrs[.type] as? FileAttributeType == .typeRegular else {
            throw ImportError.invalid
        }
        let limit = 8 * 1024 * 1024
        guard let size = attrs[.size] as? NSNumber, size.intValue <= limit else {
            throw ImportError.tooLarge
        }
        let data = try Data(contentsOf: contents, options: .mappedIfSafe)
        guard data.count <= limit else { throw ImportError.tooLarge }
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
            let plain = try text(richText)
            let children = try subnodes.map { try parse($0, depth: depth + 1) }
            return MapNode(id: id, title: plain, children: children, folded: foldNumber.boolValue)
        }
        return try maps.map { map in
            guard let main = map["mainNode"] else { throw ImportError.invalid }
            return try parse(main, depth: 0)
        }
    }

    private static func text(_ rich: String) throws -> String {
        // ponytail: text/tree/fold only; add style and attachment decoding after verified format samples.
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
