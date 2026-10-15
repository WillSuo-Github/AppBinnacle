import Foundation

enum AutoRefreshInterval: Int, CaseIterable, Identifiable, Codable, Sendable {
    case off = 0
    case every15Minutes = 15
    case every30Minutes = 30
    case every1Hour = 60
    case every4Hours = 240

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return "Off (Manual only)"
        case .every15Minutes: return "Every 15 minutes"
        case .every30Minutes: return "Every 30 minutes (Recommended)"
        case .every1Hour: return "Every 1 hour"
        case .every4Hours: return "Every 4 hours"
        }
    }

    var shortLabel: String {
        switch self {
        case .off: return "Manual"
        case .every15Minutes: return "15m"
        case .every30Minutes: return "30m"
        case .every1Hour: return "1h"
        case .every4Hours: return "4h"
        }
    }

    var timeInterval: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}
