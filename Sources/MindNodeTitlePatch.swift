import Foundation
import CoreFoundation

enum MindNodeTitlePatch {
    enum PatchError: Error { case unsupported }

    static func apply(to data: Data, original: [MapNode], edited: [MapNode]) throws -> Data {
        guard data.count <= 8 * 1024 * 1024 else { throw PatchError.unsupported }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
              format == .binary, var document = parsed as? [String: Any],
              let version = document["version"] as? NSNumber,
              CFGetTypeID(version) == CFNumberGetTypeID(),
              !["f", "d"].contains(String(cString: version.objCType)), version.intValue == 9,
              var canvas = document["canvas"] as? [String: Any],
              var maps = canvas["mindMaps"] as? [[String: Any]], maps.count == original.count,
              original.count == edited.count else { throw PatchError.unsupported }
        var changed = false
        var addedBytes = 0
        var seen = Set<UUID>()
        var count = 0
        func update(_ raw: inout [String: Any], _ before: MapNode, _ after: MapNode, depth: Int) throws {
            guard depth <= 200, count < 10_000, seen.insert(before.id).inserted else { throw PatchError.unsupported }
            count += 1
            guard before.id == after.id, let id = raw["nodeID"] as? String,
                  UUID(uuidString: id) == before.id,
                  let fold = raw["hasFoldedSubnodes"] as? NSNumber,
                  CFGetTypeID(fold) == CFBooleanGetTypeID(), fold.boolValue == before.folded,
                  var title = raw["title"] as? [String: Any],
                  let xml = title["text"] as? String,
                  var children = raw["subnodes"] as? [[String: Any]],
                  children.count == before.children.count,
                  before.children.count == after.children.count else { throw PatchError.unsupported }
            guard try MindNodeImporter.plainTitle(xml) == before.title else { throw PatchError.unsupported }
            if after.title != before.title {
                guard xml.range(of: "^<p>[^<]*</p>$", options: .regularExpression) != nil,
                      (try? XMLElement(xmlString: xml).stringValue) == before.title,
                      after.title.unicodeScalars.allSatisfy({ scalar in
                          let value = scalar.value
                          return value == 9 || value == 10 ||
                              (0x20...0xD7FF).contains(value) || (0xE000...0xFFFD).contains(value) ||
                              (0x10000...0x10FFFF).contains(value)
                      }) else { throw PatchError.unsupported }
                let replacement = XMLElement(name: "p", stringValue: after.title).xmlString(options: [])
                let bytes = replacement.utf8.count
                guard bytes <= 65_536 else { throw PatchError.unsupported }
                let increase = max(0, bytes - xml.utf8.count)
                guard increase <= 8 * 1024 * 1024 - data.count - addedBytes else { throw PatchError.unsupported }
                addedBytes += increase
                title["text"] = replacement
                raw["title"] = title
                changed = true
            }
            if after.folded != before.folded {
                raw["hasFoldedSubnodes"] = after.folded
                changed = true
            }
            for index in children.indices {
                try update(&children[index], before.children[index], after.children[index], depth: depth + 1)
            }
            raw["subnodes"] = children
        }
        for index in maps.indices {
            guard var node = maps[index]["mainNode"] as? [String: Any] else { throw PatchError.unsupported }
            try update(&node, original[index], edited[index], depth: 0)
            maps[index]["mainNode"] = node
        }
        guard changed else { return data }
        canvas["mindMaps"] = maps
        document["canvas"] = canvas
        let result = try PropertyListSerialization.data(fromPropertyList: document, format: .binary, options: 0)
        guard result.count <= 8 * 1024 * 1024 else { throw PatchError.unsupported }
        return result
    }
}
