import Foundation

enum StatusBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly = "Icon Only"
    case iconAndCost = "Icon + Cost"
    case iconAndTokens = "Icon + Tokens"
    case compact = "Icon + Cost + Tokens"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .iconOnly:
            return "Icon"
        case .iconAndCost:
            return "Cost"
        case .iconAndTokens:
            return "Tokens"
        case .compact:
            return "Compact"
        }
    }
}
