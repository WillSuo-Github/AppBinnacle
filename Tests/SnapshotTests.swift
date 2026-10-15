import Foundation
import Testing

struct SnapshotTests {
    /// A fake App Store Connect, Google sign-in, GA4, and Crashlytics backend.
    static func backend() -> MockTransport {
        MockTransport(respond)
    }

    @Sendable static func respond(_ request: URLRequest) throws -> HTTPResponse {
        let url = try #require(request.url)
        switch url.host() {
        case "api.appstoreconnect.apple.com":
            if url.path() == "/v1/salesReports" {
                return request.queryValue("filter[reportDate]") == "2026-10-11"
                    ? HTTPResponse(statusCode: 200, data: Fixtures.salesReportGzip)
                    : .json(#"{"errors":[{"status":"404","code":"NOT_FOUND"}]}"#, status: 404)
            }
            if url.path() == "/v1/apps/1234567890/customerReviews" { return .json(Fixtures.customerReviews) }
        case "oauth2.googleapis.com":
            return .json(#"{"access_token":"token-123","expires_in":3600}"#)
        case "analyticsdata.googleapis.com":
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
            #expect(url.path() == "/v1beta/properties/987654321:batchRunReports")
            return .json(Fixtures.ga4BatchResponse)
        case "firebasecrashlytics.googleapis.com":
            #expect(url.path(percentEncoded: false) == "/v1alpha/projects/1234567890/apps/1:1234567890:ios:abc123/reports/topIssues")
            #expect(request.queryValue("filter.issue.state") == "OPEN")
            #expect(request.queryValue("filter.interval.startTime") == "2026-10-06T00:00:00Z")
            #expect(request.queryValue("filter.interval.endTime") == "2026-10-13T00:00:00Z")
            return .json(Fixtures.crashlyticsTopIssues)
        default:
            break
        }
        return .json(#"{"error":{"status":"NOT_FOUND","message":"unexpected request"}}"#, status: 404)
    }

    static func service(transport: MockTransport, google: Bool = true) -> SnapshotService {
        SnapshotService(
            configuration: BinnacleConfiguration(apps: [Fixtures.weatherPal]),
            credentials: ResolvedCredentials(
                appStoreConnect: ClientTests.ascCredentials,
                google: google ? ClientTests.serviceAccount : nil),
            transport: transport,
            useSalesCache: false,
            now: Fixtures.pacificNoon("2026-10-13"))
    }

    @Test func loadsEverySourceIntoOneSnapshot() async throws {
        let transport = Self.backend()
        let snapshots = await Self.service(transport: transport).snapshots(for: [Fixtures.weatherPal], days: 7)
        let snapshot = try #require(snapshots.first)

        #expect(snapshot.sources.allSatisfy { $0.state == .ok }, "\(snapshot.sources)")
        #expect(snapshot.range == DayRange(start: Fixtures.day("2026-10-06"), end: Fixtures.day("2026-10-12")))
        #expect(snapshot.sales?.throughDay == Fixtures.day("2026-10-11"))
        #expect(snapshot.salesRange == DayRange(start: Fixtures.day("2026-10-05"), end: Fixtures.day("2026-10-11")))
        #expect(snapshot.analytics?.current.activeUsers == 800)
        #expect(snapshot.crashIssues?.count == 2)
        #expect(snapshot.reviews?.count == 3)

        let salesRequests = transport.requests.filter { $0.url?.path() == "/v1/salesReports" }
        // 14 days of comparison plus 2 days that may still be unpublished.
        #expect(salesRequests.count == 16)
        let tokenRequests = transport.requests.filter { $0.url?.host() == "oauth2.googleapis.com" }
        #expect(tokenRequests.count == 1)
    }

    @Test func briefComparesPeriodsAndCallsOutChanges() async throws {
        let snapshot = try #require(await Self.service(transport: Self.backend()).snapshots(for: [Fixtures.weatherPal], days: 7).first)
        let brief = BriefBuilder.make(from: snapshot, preferredCurrency: nil)

        let acquisition = try #require(brief.acquisition)
        #expect(acquisition.firstDownloads == MetricChange(14, 0))
        #expect(acquisition.inAppPurchases.current == 3)
        // USD comes first even though the EUR amount is larger: currencies are not compared.
        #expect(acquisition.proceeds.map(\.currency) == ["USD", "EUR"])
        #expect(BriefBuilder.make(from: snapshot, preferredCurrency: "EUR").acquisition?.proceeds.first?.currency == "EUR")
        #expect(acquisition.topCountries.map(\.country) == ["US", "CN"])
        #expect(acquisition.unclassifiedProductTypes == ["ZZ": 1])

        #expect(brief.engagement?.activeUsers.changePercent == -20)
        #expect(brief.stability?.weakestVersions.first?.version == "3.2.0")
        #expect(brief.reviews?.count == 2)
        #expect(brief.reviews?.lowRatingCount == 1)
        #expect(brief.reviews?.recentLowRatings.first?.excerpt == "Since 3.2 the app crashes every time.")

        #expect(brief.highlights.contains("Active users fell 20.0% (1,000 → 800)."))
        #expect(brief.highlights.contains("Crash-free users fell 1.00 pp to 98.50%."))
        #expect(brief.highlights.contains("Version 3.2.0 has 98.00% crash-free users (500 active users)."))
        #expect(brief.highlights.contains { $0.hasPrefix("Top open Crashlytics issue: EXC_BAD_ACCESS") })
        #expect(brief.highlights.contains("1 new 1–2★ review."))
    }

    @Test func rendersMarkdownAndJSON() async throws {
        let snapshot = try #require(await Self.service(transport: Self.backend()).snapshots(for: [Fixtures.weatherPal], days: 7).first)
        let brief = BriefBuilder.make(from: snapshot)

        let markdown = try BriefRenderer.render([brief], format: .markdown)
        #expect(markdown.hasPrefix("# Weather Pal — 2026-10-06 to 2026-10-12"))
        #expect(markdown.contains("Reports are published through 2026-10-11"))
        #expect(markdown.contains("| Active users | 800 | 1,000 | -20.0% |"))
        #expect(markdown.contains("| First downloads | 14 | 0 | n/a |"))
        #expect(markdown.contains("1. [FATAL] EXC_BAD_ACCESS in WeatherStore.refresh() — WeatherStore.swift line 88 · 120 events · 33 users"))
        #expect(markdown.contains("- Firebase Crashlytics: ok"))

        let json = try BriefRenderer.render([brief], format: .json)
        let decoded = try JSONCoding.decoder().decode(AppBrief.self, from: Data(json.utf8))
        #expect(decoded == brief)

        let csv = try BriefRenderer.render([brief], format: .csv)
        #expect(csv.contains("Weather Pal"))
        #expect(csv.contains("First Downloads"))
        #expect(csv.contains("14"))
    }

    @Test func missingSetupIsReportedPerSource() async throws {
        var app = Fixtures.weatherPal
        app.ga4PropertyID = ""
        let service = SnapshotService(
            configuration: BinnacleConfiguration(apps: [app]),
            credentials: ResolvedCredentials(google: ClientTests.serviceAccount),
            transport: Self.backend(), useSalesCache: false, now: Fixtures.pacificNoon("2026-10-13"))
        let snapshot = try #require(await service.snapshots(for: [app], days: 7).first)

        #expect(snapshot.status(of: .appStoreSales)?.state == .notConfigured)
        #expect(snapshot.status(of: .appStoreReviews)?.state == .notConfigured)
        #expect(snapshot.status(of: .googleAnalytics)?.state == .notConfigured)
        #expect(snapshot.status(of: .crashlytics)?.state == .ok)
        let markdown = BriefRenderer.markdown(BriefBuilder.make(from: snapshot))
        #expect(markdown.contains("- Google Analytics: not configured — Set this app's GA4 property ID."))
    }

    @Test func briefSaysWhenNothingIsConnected() async throws {
        let service = SnapshotService(
            configuration: BinnacleConfiguration(apps: [Fixtures.weatherPal]), credentials: ResolvedCredentials(),
            transport: Self.backend(), useSalesCache: false, now: Fixtures.pacificNoon("2026-10-13"))
        let snapshot = try #require(await service.snapshots(for: [Fixtures.weatherPal], days: 7).first)
        #expect(BriefBuilder.make(from: snapshot).highlights == ["No data sources are connected yet. See Data sources."])
    }

    @Test func failuresStayInsideTheirSource() async throws {
        let transport = MockTransport { request in
            if request.url?.host() == "oauth2.googleapis.com" {
                return .json(#"{"error":"invalid_grant","error_description":"Invalid JWT Signature."}"#, status: 400)
            }
            return try Self.respond(request)
        }
        let snapshot = try #require(await Self.service(transport: transport).snapshots(for: [Fixtures.weatherPal], days: 7).first)
        #expect(snapshot.status(of: .appStoreSales)?.state == .ok)
        #expect(snapshot.status(of: .googleAnalytics)?.state == .failed)
        #expect(snapshot.status(of: .googleAnalytics)?.detail?.contains("Invalid JWT Signature.") == true)
        #expect(BriefBuilder.make(from: snapshot).highlights.last == "Could not load: Google Analytics, Firebase Crashlytics. See Data sources.")
    }

    @Test func portfolioAggregatesMultipleSnapshots() async throws {
        let app1 = Fixtures.weatherPal
        var app2 = Fixtures.weatherPal
        app2.appleID = "9999999999"
        app2.name = "Tide Tracker"
        app2.bundleID = "com.example.tide"

        let service = Self.service(transport: Self.backend())
        let snapshots = await service.snapshots(for: [app1, app2], days: 7)
        #expect(snapshots.count == 2)

        let portfolio = PortfolioAggregator.aggregate(
            snapshots: snapshots,
            range: snapshots[0].range,
            apps: [app1, app2]
        )

        #expect(portfolio.app.appleID == "all")
        #expect(portfolio.app.name.contains("2"))
        #expect(portfolio.sales != nil)
        let dls = portfolio.sales?.total(\.firstDownloads, in: portfolio.range) ?? 0
        let app1Dls = snapshots[0].sales?.total(\.firstDownloads, in: snapshots[0].range) ?? 0
        let app2Dls = snapshots[1].sales?.total(\.firstDownloads, in: snapshots[1].range) ?? 0
        #expect(dls == app1Dls + app2Dls)

        let brief = BriefBuilder.make(from: portfolio)
        #expect(brief.acquisition?.firstDownloads.current == Double(app1Dls + app2Dls))
    }
}
