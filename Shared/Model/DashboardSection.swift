import Foundation

enum DashboardSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview
    case acquisition
    case engagement
    case stability
    case reviews
    case brief

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .acquisition: return "Downloads & Revenue"
        case .engagement: return "Engagement"
        case .stability: return "Stability"
        case .reviews: return "Reviews"
        case .brief: return "AI Brief"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .acquisition: return "arrow.down.circle"
        case .engagement: return "person.2"
        case .stability: return "bolt.heart"
        case .reviews: return "star.bubble"
        case .brief: return "text.quote"
        }
    }
}
