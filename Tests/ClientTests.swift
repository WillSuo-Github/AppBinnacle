import CryptoKit
import Foundation
import Testing

struct ClientTests {
    static let ascCredentials = AppStoreConnectCredentials(
        issuerID: "issuer-1", keyID: "KEY1234567", privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation, vendorNumber: "80012345")

    static let serviceAccount = GoogleServiceAccount(
        type: "service_account", projectID: "demo", privateKeyID: "kid-1",
        privateKey: Fixtures.testRSAPrivateKeyPEM, clientEmail: "binnacle@demo.iam.gserviceaccount.com", tokenURI: nil)

    @Test func salesReportRequestAndDecompression() async throws {
        let transport = MockTransport { request in
            request.queryValue("filter[reportDate]") == "2026-10-11"
                ? HTTPResponse(statusCode: 200, data: Fixtures.salesReportGzip)
                : .json(#"{"errors":[{"status":"404","code":"NOT_FOUND","title":"The specified resource does not exist","detail":"There were no sales for the date specified."}]}"#, status: 404)
        }
        let client = AppStoreConnectClient(credentials: Self.ascCredentials, transport: transport)

        let report = try await client.dailySalesReport(vendorNumber: "80012345", day: Fixtures.day("2026-10-11"))
        guard case .report(let text) = report else {
            Issue.record("Expected a report")
            return
        }
        #expect(text.hasPrefix("Provider\t"))
        #expect(try await client.dailySalesReport(vendorNumber: "80012345", day: Fixtures.day("2026-10-10")) == .noSales)

        let request = try #require(transport.requests.first)
        #expect(request.url?.path() == "/v1/salesReports")
        #expect(request.queryValue("filter[vendorNumber]") == "80012345")
        #expect(request.queryValue("filter[reportType]") == "SALES")
        #expect(request.queryValue("filter[reportSubType]") == "SUMMARY")
        #expect(request.queryValue("filter[frequency]") == "DAILY")
        #expect(request.queryValue("filter[version]") == "1_0")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/a-gzip")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ey") == true)
    }

    @Test func surfacesAppStoreConnectErrors() async {
        let transport = MockTransport { _ in
            .json(#"{"errors":[{"status":"401","code":"NOT_AUTHORIZED","title":"Authentication credentials are missing or invalid.","detail":"Provide a properly configured and signed bearer token."}]}"#, status: 401)
        }
        let client = AppStoreConnectClient(credentials: Self.ascCredentials, transport: transport)
        do {
            _ = try await client.apps()
            Issue.record("Expected an error")
        } catch {
            let message = error.localizedDescription
            #expect(message.contains("HTTP 401"))
            #expect(message.contains("Authentication credentials are missing or invalid."))
            #expect(message.contains("Check the issuer ID"))
        }
    }

    @Test func decodesCustomerReviews() async throws {
        let transport = MockTransport { _ in .json(Fixtures.customerReviews) }
        let reviews = try await AppStoreConnectClient(credentials: Self.ascCredentials, transport: transport)
            .customerReviews(appID: "1234567890")
        #expect(reviews.map(\.id) == ["r1", "r2", "r3"])
        #expect(reviews[0].day == Fixtures.day("2026-10-11"))
        #expect(reviews[1].day == Fixtures.day("2026-10-07"))
        #expect(transport.requests.first?.queryValue("sort") == "-createdDate")
    }

    @Test func parsesAnalyticsBatchAndFillsMissingDays() throws {
        let range = DayRange(ending: Fixtures.day("2026-10-12"), length: 7)
        let report = try AnalyticsQuery.report(from: Data(Fixtures.ga4BatchResponse.utf8), range: range)

        #expect(report.daily.count == 14)
        #expect(report.daily.first?.day == Fixtures.day("2026-09-29"))
        #expect(report.daily.first { $0.day == Fixtures.day("2026-10-06") }?.activeUsers == 120)
        #expect(report.daily.first { $0.day == Fixtures.day("2026-10-07") } == AnalyticsDay(day: Fixtures.day("2026-10-07")))
        #expect(report.daily.first { $0.day == Fixtures.day("2026-10-12") }?.crashFreeUsersRate == nil)
        #expect(report.current.activeUsers == 800)
        #expect(report.current.crashFreeUsersRate == 0.985)
        #expect(report.previous.activeUsers == 1000)
        #expect(report.versions.map(\.version) == ["3.2.0", "3.1.0"])
    }

    @Test func analyticsBatchAsksForSeparateTotals() throws {
        let range = DayRange(ending: Fixtures.day("2026-10-12"), length: 7)
        let batch = AnalyticsQuery.batch(range: range, streamID: "4455")
        #expect(batch.requests.count == 4)
        #expect(batch.requests[0].dateRanges.first?.startDate == "2026-09-29")
        #expect(batch.requests[0].keepEmptyRows == true)
        #expect(batch.requests[1].dimensions == nil)
        #expect(batch.requests[2].dateRanges.first?.endDate == "2026-10-05")
        #expect(batch.requests.allSatisfy { $0.dimensionFilter?.filter.stringFilter.value == "4455" })
        let json = String(decoding: try JSONEncoder().encode(batch), as: UTF8.self)
        #expect(json.contains(#""fieldName":"streamId""#))
        #expect(!json.contains("null"))
    }

    @Test func parsesCrashlyticsStringCounts() throws {
        let issues = try CrashlyticsResponse.issues(from: Data(Fixtures.crashlyticsTopIssues.utf8))
        #expect(issues.count == 2)
        #expect(issues[0] == CrashIssue(
            id: "abc123", title: "EXC_BAD_ACCESS in WeatherStore.refresh()", subtitle: "WeatherStore.swift line 88",
            errorType: "FATAL", consoleURL: "https://console.firebase.google.com/project/demo/crashlytics/issues/abc123",
            events: 120, impactedUsers: 33))
        #expect(issues[1].events == 7)
        #expect(issues[1].impactedUsers == 4)
    }

    @Test func googleTokenIsExchangedOnceAndReused() async throws {
        let transport = MockTransport { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(body.hasPrefix("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=ey"))
            return .json(#"{"access_token":"token-123","expires_in":3599,"token_type":"Bearer"}"#)
        }
        let provider = GoogleAccessTokenProvider(account: Self.serviceAccount, transport: transport)
        #expect(try await provider.accessToken() == "token-123")
        #expect(try await provider.accessToken() == "token-123")
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.url?.absoluteString == GoogleEndpoints.token)
    }

    @Test func surfacesGoogleSignInErrors() async {
        let transport = MockTransport { _ in
            .json(#"{"error":"invalid_grant","error_description":"Invalid JWT Signature."}"#, status: 400)
        }
        let provider = GoogleAccessTokenProvider(account: Self.serviceAccount, transport: transport)
        await #expect(throws: BinnacleError.http(service: "Google sign-in", status: 400, message: "invalid_grant: Invalid JWT Signature.")) {
            try await provider.accessToken()
        }
    }
}
