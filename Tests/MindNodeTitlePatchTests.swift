import Foundation

@main
enum MindNodeTitlePatchTests {
    static func main() throws {
        let rootID = UUID(), childID = UUID()
        let child: [String: Any] = ["nodeID": childID.uuidString, "title": ["text": "<p>Untouched <b>bold</b></p>", "style": "preserve"],
                                    "subnodes": [], "hasFoldedSubnodes": false, "link": "untouched"]
        let root: [String: Any] = ["nodeID": rootID.uuidString, "title": ["text": "<p>Old &amp; safe</p>", "style": "keep"],
                                   "subnodes": [child], "hasFoldedSubnodes": false, "unknown": ["value": 42]]
        let plist: [String: Any] = ["version": 9, "canvas": ["mindMaps": [["mainNode": root]]], "opaque": Data([0, 1, 255])]
        let originalData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let old = MapNode(id: rootID, title: "Old & safe", children: [
            MapNode(id: childID, title: "Untouched bold", children: [], folded: false)
        ], folded: false)
        var edited = old
        edited.title = "新 <标题> & emoji 🧭"
        edited.folded = true
        let result = try MindNodeTitlePatch.apply(to: originalData, original: [old], edited: [edited])
        assert(originalData != result)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let parsed = try PropertyListSerialization.propertyList(from: result, options: [], format: &format) as! [String: Any]
        assert(format == .binary)
        assert((parsed["opaque"] as? Data) == Data([0, 1, 255]))
        let changed = ((parsed["canvas"] as! [String: Any])["mindMaps"] as! [[String: Any]])[0]["mainNode"] as! [String: Any]
        assert(((changed["unknown"] as! [String: Any])["value"] as? Int) == 42)
        assert((changed["hasFoldedSubnodes"] as? Bool) == true)
        let title = changed["title"] as! [String: Any]
        assert(title["style"] as? String == "keep")
        assert(title["text"] as? String == "<p>新 &lt;标题&gt; &amp; emoji 🧭</p>")
        let untouched = (changed["subnodes"] as! [[String: Any]])[0]
        assert((untouched["title"] as! [String: Any])["text"] as? String == "<p>Untouched <b>bold</b></p>")
        assert(untouched["link"] as? String == "untouched")
        var styledRoot = root
        styledRoot["title"] = ["text": "<p style=\"font-size: 14pt\">Old &amp; safe</p>"]
        var styledPlist = plist
        styledPlist["canvas"] = ["mindMaps": [["mainNode": styledRoot]]]
        let styledData = try PropertyListSerialization.data(fromPropertyList: styledPlist, format: .binary, options: 0)
        let styledResult = try MindNodeTitlePatch.apply(to: styledData, original: [old], edited: [edited])
        let styledDecoded = try PropertyListSerialization.propertyList(from: styledResult, options: [], format: nil) as! [String: Any]
        let styledMaps = (styledDecoded["canvas"] as! [String: Any])["mindMaps"] as! [[String: Any]]
        let styledRaw = styledMaps[0]["mainNode"] as! [String: Any]
        let styledXML = (styledRaw["title"] as! [String: Any])["text"] as! String
        let styledPlain = try MindNodeImporter.plainTitle(styledXML)
        assert(styledXML.contains("style=\"font-size: 14pt\"") && styledPlain == edited.title,
               "Edited title must preserve a real v9 paragraph's formatting attribute")
        var untitledRoot = root
        untitledRoot["title"] = ["text": ""]
        var untitledPlist = plist
        untitledPlist["canvas"] = ["mindMaps": [["mainNode": untitledRoot]]]
        let untitledData = try PropertyListSerialization.data(fromPropertyList: untitledPlist, format: .binary, options: 0)
        var untitled = old
        untitled.title = ""
        var renamed = untitled
        renamed.title = "Edited empty title"
        let blankResult = try MindNodeTitlePatch.apply(to: untitledData, original: [untitled], edited: [renamed])
        let blankDecoded = try PropertyListSerialization.propertyList(from: blankResult, options: [], format: nil) as! [String: Any]
        let blankMaps = (blankDecoded["canvas"] as! [String: Any])["mindMaps"] as! [[String: Any]]
        let blankRaw = blankMaps[0]["mainNode"] as! [String: Any]
        assert((blankRaw["title"] as! [String: Any])["text"] as? String == "<p>Edited empty title</p>")
        func rejects(_ action: () throws -> Data) -> Bool {
            do { _ = try action(); return false } catch { return true }
        }
        var moved = edited
        moved.children = []
        assert(rejects { try MindNodeTitlePatch.apply(to: originalData, original: [old], edited: [moved]) })
        let secondID = UUID()
        let second: [String: Any] = ["nodeID": secondID.uuidString,
            "title": ["text": "<p style=\"font-size: 14pt\">Second</p>"],
            "subnodes": [], "hasFoldedSubnodes": false, "unknown": "keep-with-node"]
        var twoRaw = root
        twoRaw["subnodes"] = [child, second]
        var twoDocument = plist
        twoDocument["canvas"] = ["mindMaps": [["mainNode": twoRaw]]]
        let twoData = try PropertyListSerialization.data(fromPropertyList: twoDocument, format: .binary, options: 0)
        let secondNode = MapNode(id: secondID, title: "Second", children: [], folded: false)
        var twoOriginal = old
        twoOriginal.children.append(secondNode)
        var reordered = twoOriginal
        reordered.children.swapAt(0, 1)
        let reorderedData = try MindNodeTitlePatch.apply(to: twoData, original: [twoOriginal], edited: [reordered])
        let reorderedDocument = try PropertyListSerialization.propertyList(from: reorderedData, options: [], format: nil) as! [String: Any]
        let reorderedMap = (reorderedDocument["canvas"] as! [String: Any])["mindMaps"] as! [[String: Any]]
        let reorderedRoot = reorderedMap[0]["mainNode"] as! [String: Any]
        let reorderedRaw = reorderedRoot["subnodes"] as! [[String: Any]]
        assert((reorderedRaw[0]["unknown"] as? String) == "keep-with-node" &&
               (reorderedRaw[1]["link"] as? String) == "untouched" &&
               reorderedRaw.compactMap { UUID(uuidString: $0["nodeID"] as? String ?? "") } == [secondID, childID],
               "Moving existing nodes must carry their unknown metadata and preserve original IDs")
        var styled = old
        styled.children[0].title = "Rewritten"
        assert(rejects { try MindNodeTitlePatch.apply(to: originalData, original: [old], edited: [styled]) })
        var invalid = old
        invalid.title = "bad\u{1}"
        assert(rejects { try MindNodeTitlePatch.apply(to: originalData, original: [old], edited: [invalid]) })
        invalid.title = "line\rbreak"
        assert(rejects { try MindNodeTitlePatch.apply(to: originalData, original: [old], edited: [invalid]) })
        var malformedRoot = root
        malformedRoot["title"] = ["text": "<p>broken"]
        var malformed = plist
        malformed["canvas"] = ["mindMaps": [["mainNode": malformedRoot]]]
        let malformedData = try PropertyListSerialization.data(fromPropertyList: malformed, format: .binary, options: 0)
        assert(rejects { try MindNodeTitlePatch.apply(to: malformedData, original: [old], edited: [old]) })
        malformedRoot["title"] = ["text": "<p>Different</p>"]
        malformed["canvas"] = ["mindMaps": [["mainNode": malformedRoot]]]
        let mismatchedData = try PropertyListSerialization.data(fromPropertyList: malformed, format: .binary, options: 0)
        assert(rejects { try MindNodeTitlePatch.apply(to: mismatchedData, original: [old], edited: [edited]) })
        var repeatedChild = child
        repeatedChild["nodeID"] = rootID.uuidString
        var repeatedRoot = root
        repeatedRoot["subnodes"] = [repeatedChild]
        var duplicate = plist
        duplicate["canvas"] = ["mindMaps": [["mainNode": repeatedRoot]]]
        let duplicateData = try PropertyListSerialization.data(fromPropertyList: duplicate, format: .binary, options: 0)
        var repeatedModel = old
        repeatedModel.children[0].id = rootID
        assert(rejects { try MindNodeTitlePatch.apply(to: duplicateData, original: [repeatedModel], edited: [repeatedModel]) })
        var oversized = plist
        oversized["opaque"] = Data(repeating: 0, count: 8 * 1024 * 1024)
        let oversizedData = try PropertyListSerialization.data(fromPropertyList: oversized, format: .binary, options: 0)
        assert(rejects { try MindNodeTitlePatch.apply(to: oversizedData, original: [old], edited: [old]) })
        let crowdedIDs = (0..<140).map { _ in UUID() }
        var crowdedRoot = root
        crowdedRoot["subnodes"] = crowdedIDs.map { id in
            ["nodeID": id.uuidString, "title": ["text": "<p>x</p>"],
             "subnodes": [], "hasFoldedSubnodes": false] as [String: Any]
        }
        var crowdedPlist = plist
        crowdedPlist["canvas"] = ["mindMaps": [["mainNode": crowdedRoot]]]
        let crowdedData = try PropertyListSerialization.data(fromPropertyList: crowdedPlist, format: .binary, options: 0)
        let crowded = MapNode(id: rootID, title: "Old & safe", children: crowdedIDs.map {
            MapNode(id: $0, title: "x", children: [], folded: false)
        }, folded: false)
        var expanded = crowded
        for index in expanded.children.indices { expanded.children[index].title = String(repeating: "z", count: 65_000) }
        assert(rejects { try MindNodeTitlePatch.apply(to: crowdedData, original: [crowded], edited: [expanded]) })
        assert((try? MindNodeTitlePatch.apply(to: originalData, original: [old], edited: [old])) == originalData)
        print("v9 title/fold patch and unknown-field preservation passed")
    }
}
