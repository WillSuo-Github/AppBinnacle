import Foundation

struct AnalyticsDay: Codable, Equatable, Sendable {
    var day: Day
    var activeUsers = 0
    var newUsers = 0
    var sessions = 0
    var crashAffectedUsers = 0
    /// 0...1. Nil when nobody was active.
    var crashFreeUsersRate: Double?
}

struct AnalyticsTotals: Codable, Equatable, Sendable {
    var activeUsers = 0
    var newUsers = 0
    var sessions = 0
    var crashAffectedUsers = 0
    var crashFreeUsersRate: Double?
}

struct VersionStability: Codable, Equatable, Hashable, Sendable {
    var version: String
    var activeUsers: Int
    var crashAffectedUsers: Int
    var crashFreeUsersRate: Double?
}

struct AnalyticsReport: Codable, Equatable, Sendable {
    /// Every day of the previous and current periods, in ascending order.
    var daily: [AnalyticsDay]
    /// Totals for the period. Active users are de-duplicated across days by GA4.
    var current: AnalyticsTotals
    var previous: AnalyticsTotals
    /// App versions in the current period, most active first.
    var versions: [VersionStability]

    func daily(in range: DayRange) -> [AnalyticsDay] {
        daily.filter { range.contains($0.day) }
    }
}

struct AnalyticsClient: Sendable {
    static let serviceName = "Google Analytics Data API"

    var tokens: GoogleAccessTokenProvider
    var transport: any HTTPTransport = URLSessionTransport()

    func report(propertyID: String, streamID: String = "", range: DayRange) async throws -> AnalyticsReport {
        let request = AnalyticsQuery.batch(range: range, streamID: streamID)
        let data = try await post(request, propertyID: propertyID)
        return try AnalyticsQuery.report(from: data, range: range)
    }

    /// A one-number query used by the connection check.
    func activeUsers(propertyID: String, streamID: String = "", range: DayRange) async throws -> Int {
        let request = GA4BatchRequest(requests: [
            GA4Request(dateRanges: [.init(range)], metrics: [.init("activeUsers")],
                       dimensionFilter: AnalyticsQuery.streamFilter(streamID)),
        ])
        let response = try AnalyticsQuery.decode(try await post(request, propertyID: propertyID))
        return Int(response.reports?.first?.table().first?.metrics["activeUsers"] ?? 0)
    }

    private func post(_ body: GA4BatchRequest, propertyID: String) async throws -> Data {
        let property = TrackedApp.normalizedPropertyID(propertyID)
        guard !property.isEmpty, property.allSatisfy(\.isNumber),
              let url = URL(string: "\(GoogleEndpoints.analyticsData)/properties/\(property):batchRunReports")
        else {
            throw BinnacleError.invalidArgument("The GA4 property ID should be a number such as 123456789.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await GoogleAPI.send(request, service: Self.serviceName, tokens: tokens, transport: transport)
    }
}

enum AnalyticsQuery {
    static let periodMetrics = ["activeUsers", "newUsers", "sessions", "crashAffectedUsers", "crashFreeUsersRate"]

    /// Four reports in one call: daily trend for both periods, current totals, previous totals, versions.
    static func batch(range: DayRange, streamID: String) -> GA4BatchRequest {
        let filter = streamFilter(streamID)
        let metrics = periodMetrics.map(GA4Request.Field.init)
        let trend = DayRange(start: range.previous.start, end: range.end)
        return GA4BatchRequest(requests: [
            GA4Request(dateRanges: [.init(trend)], dimensions: [.init("date")], metrics: metrics,
                       dimensionFilter: filter, orderBys: [.init(dimension: .init(dimensionName: "date"))],
                       limit: 1000, keepEmptyRows: true),
            GA4Request(dateRanges: [.init(range)], metrics: metrics, dimensionFilter: filter),
            GA4Request(dateRanges: [.init(range.previous)], metrics: metrics, dimensionFilter: filter),
            GA4Request(dateRanges: [.init(range)], dimensions: [.init("appVersion")],
                       metrics: [.init("activeUsers"), .init("crashAffectedUsers"), .init("crashFreeUsersRate")],
                       dimensionFilter: filter,
                       orderBys: [.init(metric: .init(metricName: "activeUsers"), desc: true)], limit: 10),
        ])
    }

    static func streamFilter(_ streamID: String) -> GA4Request.FilterExpression? {
        let stream = streamID.trimmed
        guard !stream.isEmpty else { return nil }
        return GA4Request.FilterExpression(filter: .init(fieldName: "streamId", stringFilter: .init(matchType: "EXACT", value: stream)))
    }

    static func decode(_ data: Data) throws -> GA4BatchResponse {
        do {
            return try JSONDecoder().decode(GA4BatchResponse.self, from: data)
        } catch {
            throw BinnacleError.invalidResponse(service: AnalyticsClient.serviceName, message: String(describing: error))
        }
    }

    static func report(from data: Data, range: DayRange) throws -> AnalyticsReport {
        let reports = try decode(data).reports ?? []
        guard reports.count == 4 else {
            throw BinnacleError.invalidResponse(service: AnalyticsClient.serviceName, message: "expected 4 reports, got \(reports.count)")
        }

        var byDay: [Day: AnalyticsDay] = [:]
        for row in reports[0].table() {
            guard let day = row.dimensions["date"].flatMap(Day.init(compact:)) else { continue }
            byDay[day] = AnalyticsDay(
                day: day, activeUsers: row.int("activeUsers"), newUsers: row.int("newUsers"),
                sessions: row.int("sessions"), crashAffectedUsers: row.int("crashAffectedUsers"),
                crashFreeUsersRate: row.rate(activeUsers: row.int("activeUsers")))
        }
        // GA4 omits days it never saw, so fill the whole trend with zeros.
        let trend = DayRange(start: range.previous.start, end: range.end)
        let daily = trend.days.map { byDay[$0] ?? AnalyticsDay(day: $0) }

        let versions = reports[3].table().compactMap { row -> VersionStability? in
            guard let version = row.dimensions["appVersion"], !version.isEmpty, version != "(not set)" else { return nil }
            let active = row.int("activeUsers")
            return VersionStability(version: version, activeUsers: active, crashAffectedUsers: row.int("crashAffectedUsers"),
                                    crashFreeUsersRate: row.rate(activeUsers: active))
        }
        return AnalyticsReport(daily: daily, current: totals(reports[1]), previous: totals(reports[2]), versions: versions)
    }

    private static func totals(_ report: GA4Report) -> AnalyticsTotals {
        guard let row = report.table().first else { return AnalyticsTotals() }
        let active = row.int("activeUsers")
        return AnalyticsTotals(
            activeUsers: active, newUsers: row.int("newUsers"), sessions: row.int("sessions"),
            crashAffectedUsers: row.int("crashAffectedUsers"), crashFreeUsersRate: row.rate(activeUsers: active))
    }
}

struct GA4BatchRequest: Encodable, Sendable {
    var requests: [GA4Request]
}

struct GA4Request: Encodable, Sendable {
    struct DateRange: Encodable, Sendable {
        var startDate: String
        var endDate: String
        init(_ range: DayRange) {
            startDate = range.start.iso
            endDate = range.end.iso
        }
    }

    struct Field: Encodable, Sendable {
        var name: String
        init(_ name: String) { self.name = name }
    }

    struct OrderBy: Encodable, Sendable {
        struct DimensionOrder: Encodable, Sendable { var dimensionName: String }
        struct MetricOrder: Encodable, Sendable { var metricName: String }
        var dimension: DimensionOrder?
        var metric: MetricOrder?
        var desc: Bool?
    }

    struct FilterExpression: Encodable, Sendable {
        struct Filter: Encodable, Sendable {
            var fieldName: String
            var stringFilter: StringFilter
        }
        struct StringFilter: Encodable, Sendable {
            var matchType: String
            var value: String
        }
        var filter: Filter
    }

    var dateRanges: [DateRange]
    var dimensions: [Field]?
    var metrics: [Field]
    var dimensionFilter: FilterExpression?
    var orderBys: [OrderBy]?
    var limit: Int?
    var keepEmptyRows: Bool?
}

struct GA4BatchResponse: Decodable, Sendable {
    var reports: [GA4Report]?
}

struct GA4Report: Decodable, Sendable {
    struct Header: Decodable, Sendable { var name: String }
    struct Value: Decodable, Sendable { var value: String? }
    struct Row: Decodable, Sendable {
        var dimensionValues: [Value]?
        var metricValues: [Value]?
    }

    struct TableRow: Sendable {
        var dimensions: [String: String]
        var metrics: [String: Double]

        func int(_ metric: String) -> Int { Int((metrics[metric] ?? 0).rounded()) }

        func rate(activeUsers: Int) -> Double? {
            activeUsers > 0 ? metrics["crashFreeUsersRate"] : nil
        }
    }

    var dimensionHeaders: [Header]?
    var metricHeaders: [Header]?
    var rows: [Row]?

    func table() -> [TableRow] {
        let dimensionNames = (dimensionHeaders ?? []).map(\.name)
        let metricNames = (metricHeaders ?? []).map(\.name)
        return (rows ?? []).map { row in
            var dimensions: [String: String] = [:]
            for (name, value) in zip(dimensionNames, row.dimensionValues ?? []) { dimensions[name] = value.value ?? "" }
            var metrics: [String: Double] = [:]
            for (name, value) in zip(metricNames, row.metricValues ?? []) { metrics[name] = value.value.flatMap(Double.init) ?? 0 }
            return TableRow(dimensions: dimensions, metrics: metrics)
        }
    }
}
