import Foundation

@main
enum MapSearchTests {
    static func main() {
        let root = UUID(), folded = UUID(), hidden = UUID(), other = UUID(), second = UUID()
        let roots = [
            MapNode(id: root, title: "Café 中文", children: [
                MapNode(id: folded, title: "Résumé", children: [
                    MapNode(id: hidden, title: "深入 CAFÉ", children: [], folded: false)
                ], folded: true),
                MapNode(id: other, title: "coffee", children: [], folded: false)
            ], folded: false),
            MapNode(id: second, title: "CAFÉ again", children: [], folded: false)
        ]
        let unchanged = roots
        assert(searchTitles(roots, query: " cafe ") == [root, hidden, second],
               "Case- and accent-insensitive preorder includes folded descendants")
        assert(searchTitles(roots, query: "RÉSUMÉ") == [folded])
        assert(searchTitles(roots, query: "中文") == [root])
        assert(searchTitles(roots, query: "\n  \t").isEmpty)
        assert(searchTitles(roots, query: "missing").isEmpty)
        assert(searchTitles([], query: "cafe").isEmpty)
        assert(roots == unchanged, "Search must not mutate nodes or their folded state")
        print("title search tests passed (pure model traversal)")
    }
}
