import Foundation

enum DashboardRoute: Hashable, Sendable {
    case section(DashboardSection, appID: String?)
    case appDetail(appleID: String, appName: String)

    static func section(_ section: DashboardSection) -> DashboardRoute {
        .section(section, appID: nil)
    }
}
