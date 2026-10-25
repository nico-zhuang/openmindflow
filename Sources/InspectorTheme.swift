enum InspectorTheme: String, CaseIterable, Codable {
    case tropical, rainbow, candyland

    var rootFill: String {
        switch self {
        case .tropical, .rainbow: "#FFFFFFFF"
        case .candyland: "#EF1760FF"
        }
    }

    var branchColors: [String] {
        switch self {
        case .tropical: ["#52C6C4FF", "#FF9955FF", "#F6CC49FF", "#A94ECCFF"]
        case .rainbow: ["#7CCF8DFF", "#A9A6F0FF", "#FF9A60FF", "#46C3C9FF"]
        case .candyland: ["#A1D56FFF", "#F248A8FF", "#3EB9B6FF", "#C95A6AFF"]
        }
    }
}
