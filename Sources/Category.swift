import AppKit

enum WorkCategory: String, CaseIterable, Codable {
    case maker, manager, reactive, learning

    var displayName: String {
        switch self {
        case .maker:    return "Maker"
        case .manager:  return "Manager"
        case .reactive: return "Reactive"
        case .learning: return "Learning"
        }
    }

    var color: NSColor {
        switch self {
        case .maker:    return .systemBlue
        case .manager:  return .systemPurple
        case .reactive: return .systemPink
        case .learning: return .systemTeal
        }
    }

    var symbolName: String {
        switch self {
        case .maker:    return "hammer.fill"
        case .manager:  return "person.2.fill"
        case .reactive: return "tray.fill"
        case .learning: return "book.fill"
        }
    }
}
