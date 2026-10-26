enum InspectorTheme: String, CaseIterable, Codable {
    case tropical, rainbow, candyland
    case vintage, greyscale, teal, slate, blackberry, blackboard, coffee, swing

    var rootFill: String {
        switch self {
        case .tropical, .rainbow: "#FFFFFFFF"
        case .candyland: "#EF1760FF"
        case .vintage: "#B76052FF"
        case .greyscale: "#454B50FF"
        case .teal: "#147D80FF"
        case .slate: "#687E91FF"
        case .blackberry: "#805090FF"
        case .blackboard: "#D5C393FF"
        case .coffee: "#79543FFF"
        case .swing: "#EF745BFF"
        }
    }

    var branchColors: [String] {
        switch self {
        case .tropical: ["#52C6C4FF", "#FF9955FF", "#F6CC49FF", "#A94ECCFF"]
        case .rainbow: ["#7CCF8DFF", "#A9A6F0FF", "#FF9A60FF", "#46C3C9FF"]
        case .candyland: ["#A1D56FFF", "#F248A8FF", "#3EB9B6FF", "#C95A6AFF"]
        case .vintage: ["#AE775AFF", "#829777FF", "#C39C57FF", "#738898FF"]
        case .greyscale: ["#6C7378FF", "#93989CFF", "#50565BFF", "#AAB0B3FF"]
        case .teal: ["#178C8EFF", "#41A99EFF", "#397A90FF", "#79B5A2FF"]
        case .slate: ["#AAC5D1FF", "#DBB49EFF", "#94A9C3FF", "#B8C4AAFF"]
        case .blackberry: ["#CB91C5FF", "#B19BDDFF", "#E4A6ADFF", "#91B0CFFF"]
        case .blackboard: ["#E0B86EFF", "#91C6AFFF", "#E4A5A0FF", "#B8B7D9FF"]
        case .coffee: ["#9E704CFF", "#B48B69FF", "#718C78FF", "#AD806DFF"]
        case .swing: ["#E48166FF", "#69A7A0FF", "#D9AE55FF", "#9C85B7FF"]
        }
    }

    // nil preserves the original native system background for the three shipped themes.
    var canvasBackground: String? {
        switch self {
        case .tropical, .rainbow, .candyland: nil
        case .vintage: "#F5EBD9FF"
        case .greyscale: "#F0F1F0FF"
        case .teal: "#DDF2EFFF"
        case .slate: "#283440FF"
        case .blackberry: "#2C2138FF"
        case .blackboard: "#263B34FF"
        case .coffee: "#EFE3D2FF"
        case .swing: "#FFF1E3FF"
        }
    }

    // Applied only without imported/explicit font colors; the canvas still checks WCAG contrast.
    var rootTitleColor: String? {
        switch self {
        case .tropical, .rainbow, .candyland: nil
        case .blackboard: "#283B34FF"
        case .vintage, .greyscale, .teal, .slate, .blackberry, .coffee, .swing: "#FFFFFFFF"
        }
    }

    var branchTitleColor: String? {
        switch self {
        case .tropical, .rainbow, .candyland: nil
        case .slate, .blackberry, .blackboard: "#F6F3EDFF"
        case .vintage, .greyscale, .teal, .coffee, .swing: "#252D2CFF"
        }
    }
}
