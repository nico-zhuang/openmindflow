enum InspectorTheme: String, CaseIterable, Codable {
    case tropical, rainbow, candyland, teal, slate, coffee

    var rootFill: String {
        switch self {
        case .tropical, .rainbow: "#FFFFFFFF"
        case .candyland: "#EF1760FF"
        case .teal, .slate: "#FFFFFFFF"
        case .coffee: "#080909FF"
        }
    }

    var branchColors: [String] {
        switch self {
        case .tropical: ["#52C6C4FF", "#FF9955FF", "#F6CC49FF", "#A94ECCFF"]
        case .rainbow: ["#7CCF8DFF", "#A9A6F0FF", "#FF9A60FF", "#46C3C9FF"]
        case .candyland: ["#A1D56FFF", "#F248A8FF", "#3EB9B6FF", "#C95A6AFF"]
        case .teal: ["#B54CCBFF", "#F3A23BFF", "#DE5F70FF", "#319E94FF", "#687FDBFF", "#EF81CBFF"]
        case .slate: ["#FF9D5DFF", "#FFD448FF", "#BB62D5FF", "#F1667AFF", "#56A8D8FF", "#4BC7C9FF"]
        case .coffee: ["#ACFF00FF", "#35F445FF", "#FFFF36FF", "#00DDBBFF", "#FFAD22FF", "#32B7FDFF"]
        }
    }

    // Legacy Rainbow and Candyland continue to follow the native system background.
    var canvasBackground: String? {
        switch self {
        case .tropical: "#F5F3EFFF"
        case .rainbow, .candyland: nil
        case .teal: "#D8F9FBFF"
        case .slate: "#455C68FF"
        case .coffee: "#1F1E1BFF"
        }
    }

    // Applied only without imported/explicit font colors; the canvas still checks WCAG contrast.
    var rootTitleColor: String? {
        switch self {
        case .tropical, .rainbow, .candyland: nil
        case .teal, .slate: "#252D2CFF"
        case .coffee: "#FFFFFFFF"
        }
    }

    var branchTitleColor: String? {
        switch self {
        case .tropical, .rainbow, .candyland: nil
        case .slate, .coffee: "#F6F3EDFF"
        case .teal: "#252D2CFF"
        }
    }
}
