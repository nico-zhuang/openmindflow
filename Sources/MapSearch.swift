import Foundation

func searchTitles(_ roots: [MapNode], query: String) -> [UUID] {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    var matches: [UUID] = []
    func visit(_ nodes: [MapNode]) {
        for node in nodes {
            if node.title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive],
                                locale: .current) != nil { matches.append(node.id) }
            visit(node.children) // Fold state affects display, not searchable content.
        }
    }
    visit(roots)
    return matches
}
