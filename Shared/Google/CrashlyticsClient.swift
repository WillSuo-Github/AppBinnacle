import Foundation

struct CrashIssue: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    /// FATAL, NON_FATAL, or ANR.
    var errorType: String
    var consoleURL: String?
    var events: Int
    var impactedUsers: Int
}

/// Reads the top open issues from the Crashlytics REST API (v1alpha).
struct CrashlyticsClient: Sendable {
    static let serviceName = "Firebase Crashlytics API"

    var tokens: GoogleAccessTokenProvider
    var transport: any HTTPTransport = URLSessionTransport()

    func topOpenIssues(firebaseAppID: String, range: DayRange, limit: Int = 10, now: Date = Date()) async throws -> [CrashIssue] {
        let appID = firebaseAppID.trimmed
        guard let projectNumber = TrackedApp.projectNumber(fromFirebaseAppID: appID) else {
            throw BinnacleError.invalidArgument("The Firebase app ID should look like 1:1234567890:ios:abc123.")
        }
        // The interval includes its start and excludes its end.
        let end = min(range.end.adding(days: 1).startOfDayUTC, now)
        var components = URLComponents(string: "\(GoogleEndpoints.crashlytics)/projects/\(projectNumber)/apps/\(appID)/reports/topIssues")!
        components.queryItems = [
            URLQueryItem(name: "filter.issue.state", value: "OPEN"),
            URLQueryItem(name: "filter.interval.startTime", value: ISO8601.string(range.start.startOfDayUTC)),
            URLQueryItem(name: "filter.interval.endTime", value: ISO8601.string(end)),
            URLQueryItem(name: "pageSize", value: String(min(max(limit, 1), 100))),
        ]
        guard let url = components.url else {
            throw BinnacleError.invalidArgument("Could not build the Crashlytics request for \(appID).")
        }
        let data = try await GoogleAPI.send(URLRequest(url: url), service: Self.serviceName, tokens: tokens, transport: transport)
        return try CrashlyticsResponse.issues(from: data)
    }
}

enum CrashlyticsResponse {
    static func issues(from data: Data) throws -> [CrashIssue] {
        let report: Report
        do {
            report = try JSONDecoder().decode(Report.self, from: data)
        } catch {
            throw BinnacleError.invalidResponse(service: CrashlyticsClient.serviceName, message: String(describing: error))
        }
        return (report.groups ?? []).compactMap { group in
            guard let issue = group.issue, let id = issue.id else { return nil }
            let metrics = group.metrics ?? []
            return CrashIssue(
                id: id,
                title: issue.title ?? "Untitled issue",
                subtitle: issue.subtitle ?? "",
                errorType: issue.errorType ?? "",
                consoleURL: issue.uri,
                events: metrics.reduce(0) { $0 + ($1.eventsCount?.value ?? 0) },
                impactedUsers: metrics.reduce(0) { $0 + ($1.impactedUsersCount?.value ?? 0) })
        }
    }

    private struct Report: Decodable {
        var groups: [Group]?
    }

    private struct Group: Decodable {
        var issue: Issue?
        var metrics: [Metrics]?
    }

    private struct Issue: Decodable {
        var id: String?
        var title: String?
        var subtitle: String?
        var errorType: String?
        var uri: String?
    }

    private struct Metrics: Decodable {
        var eventsCount: FlexibleInt?
        var impactedUsersCount: FlexibleInt?
    }
}
