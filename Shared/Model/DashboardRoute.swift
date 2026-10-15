import Foundation

enum DashboardRoute: Hashable, Sendable {
    case section(DashboardSection)
    case appDetail(appleID: String, appName: String)
}
