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
        var originals: [UUID: (MapNode, [String: Any])] = [:]
        func collect(_ raw: [String: Any], _ before: MapNode, depth: Int) throws {
            guard depth <= 200, originals.count < 10_000,
                  let id = raw["nodeID"] as? String, UUID(uuidString: id) == before.id,
                  originals[before.id] == nil,
                  let fold = raw["hasFoldedSubnodes"] as? NSNumber,
                  CFGetTypeID(fold) == CFBooleanGetTypeID(), fold.boolValue == before.folded,
                  let xml = (raw["title"] as? [String: Any])?["text"] as? String,
                  let children = raw["subnodes"] as? [[String: Any]],
                  try MindNodeImporter.plainTitle(xml) == before.title else { throw PatchError.unsupported }
            guard children.count == before.children.count else { throw PatchError.unsupported }
            originals[before.id] = (before, raw)
            for (child, model) in zip(children, before.children) { try collect(child, model, depth: depth + 1) }
        }
        for (map, before) in zip(maps, original) {
            guard let raw = map["mainNode"] as? [String: Any] else { throw PatchError.unsupported }
            try collect(raw, before, depth: 0)
        }
        var seen = Set<UUID>()
        func update(_ raw: inout [String: Any], _ before: MapNode, _ after: MapNode, depth: Int) throws {
            var safeComparison = after
            safeComparison.title = before.title
            safeComparison.folded = before.folded
            safeComparison.children = before.children
            guard depth <= 200, seen.count < 10_000, seen.insert(before.id).inserted,
                  safeComparison == before,
                  Set(after.children.map(\.id)) == Set(before.children.map(\.id)),
                  after.children.count == before.children.count else { throw PatchError.unsupported }
            guard before.id == after.id, let id = raw["nodeID"] as? String,
                  UUID(uuidString: id) == before.id,
                  let fold = raw["hasFoldedSubnodes"] as? NSNumber,
                  CFGetTypeID(fold) == CFBooleanGetTypeID(), fold.boolValue == before.folded,
                  var title = raw["title"] as? [String: Any],
                  let xml = title["text"] as? String,
                  raw["subnodes"] is [[String: Any]],
                  before.id == after.id else { throw PatchError.unsupported }
            guard try MindNodeImporter.plainTitle(xml) == before.title else { throw PatchError.unsupported }
            if after.title != before.title {
                let paragraph: XMLElement
                if xml.isEmpty {
                    paragraph = XMLElement(name: "p")
                } else {
                    guard let existing = try? XMLElement(xmlString: xml), existing.name == "p",
                          (existing.children ?? []).allSatisfy({ $0.kind == .text }),
                          existing.stringValue == before.title else { throw PatchError.unsupported }
                    paragraph = existing // Retain paragraph attributes such as real MindNode font styling.
                }
                guard after.title.unicodeScalars.allSatisfy({ scalar in
                          let value = scalar.value
                          return value == 9 || value == 10 ||
                              (0x20...0xD7FF).contains(value) || (0xE000...0xFFFD).contains(value) ||
                              (0x10000...0x10FFFF).contains(value)
                      }) else { throw PatchError.unsupported }
                paragraph.stringValue = after.title
                let replacement = after.title.isEmpty ? "" : paragraph.xmlString(options: [])
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
            var children: [[String: Any]] = []
            for child in after.children {
                guard let (old, stored) = originals[child.id] else { throw PatchError.unsupported }
                var rawChild = stored
                try update(&rawChild, old, child, depth: depth + 1)
                children.append(rawChild)
            }
            if before.children.map(\.id) != after.children.map(\.id) { changed = true }
            raw["subnodes"] = children
        }
        for index in maps.indices {
            guard var node = maps[index]["mainNode"] as? [String: Any] else { throw PatchError.unsupported }
            try update(&node, original[index], edited[index], depth: 0)
            maps[index]["mainNode"] = node
        }
        guard seen.count == originals.count else { throw PatchError.unsupported }
        guard changed else { return data }
        canvas["mindMaps"] = maps
        document["canvas"] = canvas
        let result = try PropertyListSerialization.data(fromPropertyList: document, format: .binary, options: 0)
        guard result.count <= 8 * 1024 * 1024 else { throw PatchError.unsupported }
        return result
    }
}
