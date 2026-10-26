enum InspectorTheme: String, CaseIterable, Codable {
    case tropical, rainbow, candyland
    case vintage, greyscale, teal, slate, blackberry, blackboard, coffee, swing

    var rootFill: String {
        switch self {
        case .tropical, .rainbow: "#FFFFFFFF"
        case .candyland: "#EF1760FF"
        case .vintage: "#564541FF"
        case .greyscale: "#FAFAFAFF"
        case .teal, .slate: "#FFFFFFFF"
        case .blackberry: "#202020FF"
        case .blackboard: "#101310FF"
        case .coffee: "#080909FF"
        case .swing: "#443449FF"
        }
    }

    var branchColors: [String] {
        switch self {
        case .tropical: ["#52C6C4FF", "#FF9955FF", "#F6CC49FF", "#A94ECCFF"]
        case .rainbow: ["#7CCF8DFF", "#A9A6F0FF", "#FF9A60FF", "#46C3C9FF"]
        case .candyland: ["#A1D56FFF", "#F248A8FF", "#3EB9B6FF", "#C95A6AFF"]
        case .vintage: ["#94B531FF", "#359780FF", "#2A9CB2FF", "#C05027FF", "#B765A1FF", "#A36A30FF"]
        case .greyscale: ["#444444FF", "#545454FF", "#626262FF", "#737373FF", "#4B4B4BFF", "#5B5B5BFF"]
        case .teal: ["#B54CCBFF", "#F3A23BFF", "#DE5F70FF", "#319E94FF", "#687FDBFF", "#EF81CBFF"]
        case .slate: ["#FF9D5DFF", "#FFD448FF", "#BB62D5FF", "#F1667AFF", "#56A8D8FF", "#4BC7C9FF"]
        case .blackberry: ["#55C9C5FF", "#FFA461FF", "#EC5884FF", "#66ADEEFF", "#FBCB45FF", "#CF59DCFF"]
        case .blackboard: ["#C65276FF", "#EE8859FF", "#AF67B9FF", "#D6B44BFF", "#6E9CE3FF", "#A6BE4BFF"]
        case .coffee: ["#ACFF00FF", "#35F445FF", "#FFFF36FF", "#00DDBBFF", "#FFAD22FF", "#32B7FDFF"]
        case .swing: ["#D2A949FF", "#FFA64DFF", "#F0F075FF", "#EF7058FF", "#25ABA3FF", "#198CBFFF"]
        }
    }

    // nil preserves the original native system background for the three shipped themes.
    var canvasBackground: String? {
        switch self {
        case .tropical, .rainbow, .candyland: nil
        case .vintage: "#FAFAF8FF"
        case .greyscale: "#EFEFEFFF"
        case .teal: "#D8F9FBFF"
        case .slate: "#455C68FF"
        case .blackberry: "#39132EFF"
        case .blackboard: "#12251AFF"
        case .coffee: "#1F1E1BFF"
        case .swing: "#171119FF"
        }
    }

    // Applied only without imported/explicit font colors; the canvas still checks WCAG contrast.
    var rootTitleColor: String? {
        switch self {
        case .tropical, .rainbow, .candyland: nil
        case .greyscale, .teal, .slate: "#252D2CFF"
        case .vintage, .blackberry, .blackboard, .coffee, .swing: "#FFFFFFFF"
        }
    }

    var branchTitleColor: String? {
        switch self {
        case .tropical, .rainbow, .candyland: nil
        case .slate, .blackberry, .blackboard, .coffee, .swing: "#F6F3EDFF"
        case .vintage, .greyscale, .teal: "#252D2CFF"
        }
    }
}
