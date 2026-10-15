import Foundation

enum DataSource: String, Codable, CaseIterable, Sendable {
    case appStoreSales
    case appStoreReviews
    case googleAnalytics
    case crashlytics

    var title: String {
        switch self {
        case .appStoreSales: return "App Store sales"
        case .appStoreReviews: return "App Store reviews"
        case .googleAnalytics: return "Google Analytics"
        case .crashlytics: return "Firebase Crashlytics"
        }
    }
}

struct SourceStatus: Codable, Equatable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case ok
        case notConfigured
        case failed
    }

    var source: DataSource
    var state: State
    var detail: String?
    var lastSyncedAt: Date?

    init(source: DataSource, state: State, detail: String? = nil, lastSyncedAt: Date? = nil) {
        self.source = source
        self.state = state
        self.detail = detail
        self.lastSyncedAt = lastSyncedAt
    }
}

/// Everything AppBinnacle knows about one app for one period.
struct DashboardSnapshot: Codable, Equatable, Sendable {
    var app: TrackedApp
    var generatedAt: Date
    /// The requested period. Sales may end earlier; see sales.throughDay.
    var range: DayRange
    var sales: SalesSeries?
    var analytics: AnalyticsReport?
    var crashIssues: [CrashIssue]?
    var reviews: [CustomerReview]?
    var sources: [SourceStatus]

    var previousRange: DayRange { range.previous }

    /// The sales period, shifted back when Apple has not published the latest reports yet.
    var salesRange: DayRange? {
        sales.map { DayRange(ending: $0.throughDay, length: range.length) }
    }

    func status(of source: DataSource) -> SourceStatus? {
        sources.first { $0.source == source }
    }
}

enum Outcome<Value: Sendable>: Sendable {
    case success(Value)
    case notConfigured(String)
    case failure(String)
}

struct SnapshotService: Sendable {
    var configuration: BinnacleConfiguration
    var credentials: ResolvedCredentials
    var transport: any HTTPTransport
    var useSalesCache: Bool
    var now: Date

    init(configuration: BinnacleConfiguration, credentials: ResolvedCredentials,
         transport: any HTTPTransport = URLSessionTransport(), useSalesCache: Bool = true, now: Date = Date()) {
        self.configuration = configuration
        self.credentials = credentials
        self.transport = transport
        self.useSalesCache = useSalesCache
        self.now = now
    }

    var today: Day { Day(date: now, timeZone: .appStoreReporting) }

    /// Loads snapshots for several apps, downloading each vendor-wide sales report once.
    func snapshots(for apps: [TrackedApp], days: Int, end: Day? = nil) async -> [DashboardSnapshot] {
        let today = today
        let range = DayRange(ending: end ?? today.adding(days: -1), length: max(days, 1))
        // Sales may shift back by up to two unpublished days, so fetch two extra days.
        let salesFetch = DayRange(start: range.previous.start.adding(days: -2), end: range.end)
        let sales = await loadSalesReports(salesFetch, today: today)
        let google = credentials.google.map { GoogleAccessTokenProvider(account: $0, transport: transport) }

        return await withTaskGroup(of: (Int, DashboardSnapshot).self) { group in
            for (index, app) in apps.enumerated() {
                group.addTask {
                    (index, await self.snapshot(for: app, range: range, today: today,
                                                sales: sales, salesFetch: salesFetch, google: google))
                }
            }
            var results: [(Int, DashboardSnapshot)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func snapshot(for app: TrackedApp, range: DayRange, today: Day, sales: Outcome<[Day: ParsedSalesReport]>,
                          salesFetch: DayRange, google: GoogleAccessTokenProvider?) async -> DashboardSnapshot {
        async let reviewsOutcome = loadReviews(app)
        async let analyticsOutcome = loadAnalytics(app, range: range, google: google)
        async let issuesOutcome = loadCrashIssues(app, range: range, google: google)

        var snapshot = DashboardSnapshot(app: app, generatedAt: now, range: range, sources: [])

        switch sales {
        case .success(let reports):
            let series = SalesAggregator.series(app: app, reports: reports, fetched: salesFetch, requestedEnd: range.end, today: today)
            snapshot.sales = series
            var notes: [String] = []
            if series.throughDay < range.end { notes.append("Reports are published through \(series.throughDay.iso).") }
            if app.sku.trimmed.isEmpty { notes.append("Set the app's SKU to include in-app purchases.") }
            snapshot.sources.append(SourceStatus(source: .appStoreSales, state: .ok, detail: notes.isEmpty ? nil : notes.joined(separator: " "), lastSyncedAt: now))
        case .notConfigured(let reason):
            snapshot.sources.append(SourceStatus(source: .appStoreSales, state: .notConfigured, detail: reason))
        case .failure(let reason):
            snapshot.sources.append(SourceStatus(source: .appStoreSales, state: .failed, detail: reason))
        }

        snapshot.reviews = record(await reviewsOutcome, as: .appStoreReviews, in: &snapshot)
        snapshot.analytics = record(await analyticsOutcome, as: .googleAnalytics, in: &snapshot)
        snapshot.crashIssues = record(await issuesOutcome, as: .crashlytics, in: &snapshot)
        return snapshot
    }

    private func record<Value>(_ outcome: Outcome<Value>, as source: DataSource, in snapshot: inout DashboardSnapshot) -> Value? {
        switch outcome {
        case .success(let value):
            snapshot.sources.append(SourceStatus(source: source, state: .ok, lastSyncedAt: now))
            return value
        case .notConfigured(let reason):
            snapshot.sources.append(SourceStatus(source: source, state: .notConfigured, detail: reason))
        case .failure(let reason):
            snapshot.sources.append(SourceStatus(source: source, state: .failed, detail: reason))
        }
        return nil
    }

    private func loadSalesReports(_ fetch: DayRange, today: Day) async -> Outcome<[Day: ParsedSalesReport]> {
        guard let asc = credentials.appStoreConnect else {
            return .notConfigured("Add an App Store Connect API key to load sales.")
        }
        guard !asc.vendorNumber.isEmpty else {
            return .notConfigured("Add your vendor number (Payments and Financial Reports in App Store Connect) to load sales.")
        }
        let loader = SalesReportLoader(
            client: AppStoreConnectClient(credentials: asc, transport: transport),
            vendorNumber: asc.vendorNumber,
            cache: useSalesCache ? SalesReportCache.standard(vendorNumber: asc.vendorNumber) : nil)
        do {
            let responses = try await loader.load(days: fetch.days, today: today)
            var parsed: [Day: ParsedSalesReport] = [:]
            for (day, response) in responses {
                switch response {
                case .noSales: parsed[day] = .noSales
                case .report(let text): parsed[day] = .rows(try SalesReportParser.parse(text))
                }
            }
            return .success(parsed)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func loadReviews(_ app: TrackedApp) async -> Outcome<[CustomerReview]> {
        guard let asc = credentials.appStoreConnect else {
            return .notConfigured("Add an App Store Connect API key to load reviews.")
        }
        do {
            return .success(try await AppStoreConnectClient(credentials: asc, transport: transport).customerReviews(appID: app.appleID))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func loadAnalytics(_ app: TrackedApp, range: DayRange, google: GoogleAccessTokenProvider?) async -> Outcome<AnalyticsReport> {
        guard let google else { return .notConfigured("Import a Google service account to load Analytics.") }
        guard !app.ga4PropertyID.trimmed.isEmpty else { return .notConfigured("Set this app's GA4 property ID.") }
        do {
            let client = AnalyticsClient(tokens: google, transport: transport)
            return .success(try await client.report(propertyID: app.ga4PropertyID, streamID: app.ga4StreamID, range: range))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func loadCrashIssues(_ app: TrackedApp, range: DayRange, google: GoogleAccessTokenProvider?) async -> Outcome<[CrashIssue]> {
        guard let google else { return .notConfigured("Import a Google service account to load Crashlytics issues.") }
        guard !app.firebaseAppID.trimmed.isEmpty else { return .notConfigured("Set this app's Firebase app ID.") }
        do {
            let client = CrashlyticsClient(tokens: google, transport: transport)
            return .success(try await client.topOpenIssues(firebaseAppID: app.firebaseAppID, range: range, now: now))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

/// Keeps the latest snapshot per app and period so the dashboard opens instantly.
struct SnapshotCache: Sendable {
    var directory: URL

    static var standard: SnapshotCache {
        SnapshotCache(directory: BinnaclePaths.caches.appending(path: "snapshots"))
    }

    func load(appleID: String, days: Int) -> DashboardSnapshot? {
        guard let data = try? Data(contentsOf: file(appleID: appleID, days: days)) else { return nil }
        return try? JSONCoding.decoder().decode(DashboardSnapshot.self, from: data)
    }

    func save(_ snapshot: DashboardSnapshot) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONCoding.encoder().encode(snapshot)
                .write(to: file(appleID: snapshot.app.appleID, days: snapshot.range.length), options: .atomic)
        } catch {
            // A missing cache only means the next launch starts empty.
        }
    }

    private func file(appleID: String, days: Int) -> URL {
        directory.appending(path: "\(appleID.filter { $0.isNumber || $0.isLetter })-\(days)d.json")
    }
}
