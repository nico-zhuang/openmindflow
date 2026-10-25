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

struct MindNodeFontMetadata {
    let family: String?
    let pointSize: Double?
    let color: [Double]?
    let alignment: String?
    let alignmentCode: Int? // Theme enum meaning is undocumented; do not guess a CSS alignment.
    let bold: Bool?
    let italic: Bool?
}

struct MindNodePresentation {
    let location: CGPoint?
    let maxWidth: Double?
    let allowToShrinkWidth: Bool?
    let font: MindNodeFontMetadata?
    let styleChangedByUser: Bool?
    let fillColor: [Double]?
}

struct MindNodeThemeStyle {
    let font: MindNodeFontMetadata?
    let fillColor: [Double]?
    let stroke: MindNodeVisualStyle?
}

struct MindNodeThemeMetadata {
    let identifier: UUID?
    let backgroundColor: [Double]?
    let allowNodeStrokeColorVariation: Bool?
    let baseSubnode: MindNodeThemeStyle?
    let mainNodes: [MindNodeThemeStyle]
    let subnodeLevels: [MindNodeThemeStyle]
}

struct MindNodeDetailedImport {
    let roots: [MapNode]
    let styles: [UUID: MindNodeVisualStyle]
    let presentation: [UUID: MindNodePresentation]
    let theme: MindNodeThemeMetadata?
    var hasUnimportedConnections = false
    var hasUnimportedAttachments = false
    var hasUnimportedRichTitles = false
    var hasUnimportedTheme = false
}

enum MindNodeImporter {
    static func load(_ url: URL) throws -> [MapNode] { try loadDetailed(url).roots }

    static func loadWithStyles(_ url: URL) throws -> (roots: [MapNode], styles: [UUID: MindNodeVisualStyle]) {
        let detail = try loadDetailed(url)
        return (detail.roots, detail.styles)
    }

    static func loadDetailed(_ url: URL) throws -> MindNodeDetailedImport {
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
        var presentation: [UUID: MindNodePresentation] = [:]
        var count = 0
        var hasUnimportedAttachments = false
        var hasUnimportedRichTitles = false
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
            if node["attachment"] != nil { hasUnimportedAttachments = true }
            styles[id] = visualStyle((node["pathStyle"] as? [String: Any])?["strokeStyle"])
            let parsed = try parsedTitle(richText)
            let unknownCSS = parsed.css.map { css in
                css.split(separator: ";").contains { declaration in
                    let key = declaration.split(separator: ":", maxSplits: 1).first?
                        .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
                    return !["font", "color", "text-align"].contains(key)
                }
            } ?? false
            if parsed.rich || unknownCSS { hasUnimportedRichTitles = true }
            let location = (node["location"] as? String).flatMap(point)
            let maxWidth = number(title["maxWidth"], range: 1...100_000)
            let shrink = boolean(title["allowToShrinkWidth"])
            let changed = boolean(node["styleChangedByUser"])
            let fill = color((node["shapeStyle"] as? [String: Any])?["fillColor"])
            let titleFont = cssFont(parsed.css)
            presentation[id] = MindNodePresentation(location: location, maxWidth: maxWidth,
                allowToShrinkWidth: shrink, font: titleFont,
                styleChangedByUser: changed, fillColor: fill)
            let children = try subnodes.map { try parse($0, depth: depth + 1) }
            let fixedWidth: CGFloat? = shrink == false ? maxWidth.flatMap { value in
                let width = CGFloat(value)
                return MapNode.validWidth(width) ? width : nil
            } : nil
            return MapNode(id: id, title: parsed.text, children: children,
                           folded: foldNumber.boolValue, width: fixedWidth,
                           location: location.map { SIMD2(Double($0.x), Double($0.y)) },
                           fontFamily: titleFont?.family, fontSize: titleFont?.pointSize)
        }
        let roots = try maps.map { map in
            guard let main = map["mainNode"] else { throw ImportError.invalid }
            return try parse(main, depth: 0)
        }
        let sourceTheme = kind == .typeDirectory ? theme(at: url) : nil
        var detailed = MindNodeDetailedImport(roots: roots, styles: styles, presentation: presentation,
                                      theme: sourceTheme)
        detailed.hasUnimportedRichTitles = hasUnimportedRichTitles
        detailed.hasUnimportedTheme = kind == .typeDirectory &&
            FileManager.default.fileExists(atPath: url.appendingPathComponent("style.mindnodestyle").path) &&
            sourceTheme == nil
        detailed.hasUnimportedConnections = canvas["crossConnections"].map {
            ($0 as? [Any])?.isEmpty != true
        } ?? false
        detailed.hasUnimportedAttachments = hasUnimportedAttachments
        return detailed
    }

    static func plainTitle(_ rich: String) throws -> String { try parsedTitle(rich).text }

    private static func parsedTitle(_ rich: String) throws -> (text: String, css: String?, rich: Bool) {
        if rich.isEmpty { return ("", nil, false) } // Real v9 packages use an empty string for untitled nodes.
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
        return (handler.value, handler.css, handler.hasRichMarkup)
    }

    private static func number(_ value: Any?, range: ClosedRange<Double>) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFNumberGetTypeID(),
              n.doubleValue.isFinite, range.contains(n.doubleValue) else { return nil }
        return n.doubleValue
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    private static func tuple(_ raw: String?, count: Int) -> [Double]? {
        guard let raw, raw.first == "{", raw.last == "}" else { return nil }
        let parts = raw.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == count else { return nil }
        let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return values.count == count && values.allSatisfy(\.isFinite) ? values : nil
    }

    private static func point(_ raw: String) -> CGPoint? {
        guard let v = tuple(raw, count: 2), v.allSatisfy({ abs($0) <= 1_000_000 }) else { return nil }
        return CGPoint(x: v[0], y: v[1])
    }

    private static func color(_ value: Any?) -> [Double]? {
        guard let v = tuple(value as? String, count: 4), v.allSatisfy({ (0...1).contains($0) }) else { return nil }
        return v
    }

    private static func visualStyle(_ value: Any?) -> MindNodeVisualStyle? {
        guard let stroke = value as? [String: Any], let rgba = color(stroke["color"]),
              let width = number(stroke["width"], range: 0.5...16) else { return nil }
        return MindNodeVisualStyle(rgba: rgba, width: CGFloat(width))
    }

    private static func safeFamily(_ value: String) -> String? {
        let family = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        guard !family.isEmpty, family.count <= 80,
              family.unicodeScalars.allSatisfy({ CharacterSet.letters.union(.decimalDigits)
                  .union(CharacterSet(charactersIn: " -_.")).contains($0) }) else { return nil }
        return family
    }

    private static func cssFont(_ css: String?) -> MindNodeFontMetadata? {
        guard let css, css.utf8.count <= 4096 else { return nil }
        let entries = css.split(separator: ";").compactMap { item -> (String, String)? in
            let parts = item.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (parts[0].trimmingCharacters(in: .whitespaces).lowercased(),
                    parts[1].trimmingCharacters(in: .whitespaces))
        }
        var family: String?, size: Double?, rgba: [Double]?, align: String?
        for (key, value) in entries {
            switch key {
            case "font":
                let parts = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2, parts[0].hasSuffix("px"),
                   let n = Double(parts[0].dropLast(2)), (1...512).contains(n),
                   let safe = safeFamily(String(parts[1])) {
                    size = n; family = safe
                }
            case "color":
                if value.hasPrefix("rgba("), value.hasSuffix(")") {
                    let parts = value.dropFirst(5).dropLast().split(separator: ",", omittingEmptySubsequences: false)
                    if parts.count == 4, let a = Double(parts[3].trimmingCharacters(in: .whitespaces)),
                       a.isFinite, (0...1).contains(a) {
                        let channels = parts.prefix(3).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                        if channels.count == 3, channels.allSatisfy({ $0.isFinite && (0...255).contains($0) }) {
                            rgba = channels.map { $0 / 255 } + [a]
                        }
                    }
                }
            case "text-align": if ["left", "center", "right", "justify"].contains(value) { align = value }
            default: break
            }
        }
        guard family != nil || size != nil || rgba != nil || align != nil else { return nil }
        return MindNodeFontMetadata(family: family, pointSize: size, color: rgba,
                                    alignment: align, alignmentCode: nil, bold: nil, italic: nil)
    }

    private static func themeFont(_ value: Any?) -> MindNodeFontMetadata? {
        guard let style = value as? [String: Any] else { return nil }
        let family = (style["fontName"] as? String).flatMap(safeFamily)
        let size = number(style["fontSize"], range: 1...512)
        let rgba = color(style["color"])
        let alignmentCode = number(style["alignment"], range: 0...3).flatMap { n -> Int? in
            n.rounded() == n ? Int(n) : nil
        }
        let bold = boolean(style["bold"]), italic = boolean(style["italic"])
        guard family != nil || size != nil || rgba != nil || alignmentCode != nil || bold != nil || italic != nil else { return nil }
        return MindNodeFontMetadata(family: family, pointSize: size, color: rgba,
                                    alignment: nil, alignmentCode: alignmentCode, bold: bold, italic: italic)
    }

    private static func themeStyle(_ value: Any?) -> MindNodeThemeStyle? {
        guard let dict = value as? [String: Any] else { return nil }
        return MindNodeThemeStyle(font: themeFont(dict["titleStyle"]),
                                  fillColor: color((dict["shapeStyle"] as? [String: Any])?["fillColor"]),
                                  stroke: visualStyle(dict["strokeStyle"]))
    }

    private static func theme(at package: URL) -> MindNodeThemeMetadata? {
        let directory = package.appendingPathComponent("style.mindnodestyle")
        let file = directory.appendingPathComponent("contents.xml")
        let fm = FileManager.default
        guard (try? fm.attributesOfItem(atPath: directory.path)[.type]) as? FileAttributeType == .typeDirectory else { return nil }
        let identityFile = directory.appendingPathComponent("metadata.plist")
        var identity: UUID?
        if let attrs = try? fm.attributesOfItem(atPath: identityFile.path),
           attrs[.type] as? FileAttributeType == .typeRegular,
           let size = attrs[.size] as? NSNumber, size.uint64Value <= 64 * 1024,
           let data = try? Data(contentsOf: identityFile), data.count <= 64 * 1024,
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let fields = plist as? [String: Any], let raw = fields["id"] as? String {
            identity = UUID(uuidString: raw)
        }
        guard let attrs = try? fm.attributesOfItem(atPath: file.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              let size = attrs[.size] as? NSNumber, size.uint64Value <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: file, options: .mappedIfSafe), data.count <= 8 * 1024 * 1024 else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: &format),
              let dict = plist as? [String: Any] else { return nil }
        let main = (dict["mainNodes"] as? [Any])?.prefix(100).compactMap(themeStyle) ?? []
        let levels = (dict["subnodeLevels"] as? [Any])?.prefix(100).compactMap(themeStyle) ?? []
        return MindNodeThemeMetadata(identifier: identity, backgroundColor: color(dict["backgroundColor"]),
            allowNodeStrokeColorVariation: boolean(dict["allowNodeStrokeColorVariation"]),
            baseSubnode: themeStyle(dict["baseSubnode"]), mainNodes: main, subnodeLevels: levels)
    }
}

private final class PlainTitle: NSObject, XMLParserDelegate {
    var value = ""
    var css: String?
    var depth = 0
    var hasRoot = false
    var valid = true
    var hasRichMarkup = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard depth < 64 else { valid = false; parser.abortParsing(); return }
        if depth == 0 {
            hasRoot = true
            css = attributeDict["style"]
            if elementName != "p" { valid = false }
            if attributeDict.keys.contains(where: { $0 != "style" }) { hasRichMarkup = true }
        } else if elementName != "br" || !attributeDict.isEmpty { hasRichMarkup = true }
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
