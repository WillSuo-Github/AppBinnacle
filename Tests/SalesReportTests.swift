import Foundation
import Testing

struct GzipTests {
    @Test func decodesStreamWithoutFileName() throws {
        let data = try Gzip.decompress(Data(base64Encoded: Fixtures.helloGzipBase64)!)
        #expect(String(decoding: data, as: UTF8.self) == "Hello, AppBinnacle!\n")
    }

    @Test func decodesStreamWithStoredFileName() throws {
        #expect(Gzip.isGzip(Fixtures.salesReportGzip))
        let text = String(decoding: try Gzip.decompress(Fixtures.salesReportGzip), as: UTF8.self)
        #expect(text.hasPrefix("Provider\tProvider Country\tSKU"))
    }

    @Test func rejectsCorruptedData() {
        var bytes = [UInt8](Fixtures.salesReportGzip)
        bytes[bytes.count / 2] ^= 0xFF
        #expect(throws: BinnacleError.self) { try Gzip.decompress(Data(bytes)) }
        #expect(throws: BinnacleError.self) { try Gzip.decompress(Data("plain text, not gzip".utf8)) }
    }
}

struct SalesReportTests {
    private func rows() throws -> [SalesReportRow] {
        try SalesReportParser.parse(String(decoding: try Gzip.decompress(Fixtures.salesReportGzip), as: UTF8.self))
    }

    @Test func classifiesDocumentedProductTypes() {
        for code in ["1", "1F", "1T", "F1"] { #expect(SalesCategory(productType: code) == .firstDownload) }
        for code in ["3", "3F", "F3"] { #expect(SalesCategory(productType: code) == .redownload) }
        for code in ["7", "7F", "7T", "F7"] { #expect(SalesCategory(productType: code) == .update) }
        for code in ["IA1", "IA9", "IAY", "FI1"] { #expect(SalesCategory(productType: code) == .inAppPurchase) }
        // Codes that are absent from Apple's current table are not guessed.
        for code in ["1-B", "3T", "IAC", "ZZ", ""] { #expect(SalesCategory(productType: code) == .other) }
    }

    @Test func parsesEveryRowByColumnName() throws {
        let rows = try rows()
        #expect(rows.count == 9)
        let purchase = try #require(rows.first { $0.productType == "IA1" })
        #expect(purchase.units == 3)
        #expect(purchase.developerProceeds == Decimal(string: "0.70"))
        #expect(purchase.parentIdentifier == "WEATHERPAL")
        #expect(rows.last?.units == -1)
    }

    @Test func summarizesOnlyTheTrackedApp() throws {
        let summary = SalesAggregator.summarize(try rows(), day: Fixtures.day("2026-10-11"), app: Fixtures.weatherPal)
        #expect(summary.firstDownloads == 14)
        #expect(summary.firstDownloadsByCountry == ["US": 10, "CN": 4])
        #expect(summary.redownloads == 2)
        #expect(summary.updates == 30)
        // 3 purchases + 1 subscription - 1 refund
        #expect(summary.inAppPurchases == 3)
        #expect(summary.otherProductTypes == ["ZZ": 1])
        #expect(summary.proceeds["USD"] == Decimal(string: "1.40"))
        #expect(summary.proceeds["EUR"] == Decimal(string: "6.30"))
    }

    @Test func inAppPurchasesNeedTheAppSKU() throws {
        var app = Fixtures.weatherPal
        app.sku = ""
        let summary = SalesAggregator.summarize(try rows(), day: Fixtures.day("2026-10-11"), app: app)
        #expect(summary.firstDownloads == 14)
        #expect(summary.inAppPurchases == 0)
        #expect(summary.proceeds.isEmpty)
    }

    @Test func recentMissingReportsArePendingNotZero() throws {
        let fetched = DayRange(start: Fixtures.day("2026-10-03"), end: Fixtures.day("2026-10-12"))
        var reports: [Day: ParsedSalesReport] = [:]
        for day in fetched.days { reports[day] = .noSales }
        reports[Fixtures.day("2026-10-11")] = .rows(try rows())

        let series = SalesAggregator.series(app: Fixtures.weatherPal, reports: reports, fetched: fetched,
                                            requestedEnd: Fixtures.day("2026-10-12"), today: Fixtures.day("2026-10-13"))
        #expect(series.throughDay == Fixtures.day("2026-10-11"))
        #expect(series.pendingDays == [Fixtures.day("2026-10-12")])
        #expect(series.days.count == 9)
        #expect(series.total(\.firstDownloads, in: DayRange(ending: series.throughDay, length: 7)) == 14)
    }

    @Test func olderMissingReportsCountAsNoSales() {
        let fetched = DayRange(start: Fixtures.day("2026-10-03"), end: Fixtures.day("2026-10-12"))
        let series = SalesAggregator.series(app: Fixtures.weatherPal, reports: [:], fetched: fetched,
                                            requestedEnd: Fixtures.day("2026-10-12"), today: Fixtures.day("2026-10-20"))
        #expect(series.throughDay == Fixtures.day("2026-10-12"))
        #expect(series.pendingDays.isEmpty)
        #expect(series.days.allSatisfy { $0.firstDownloads == 0 })
    }

    @Test func cacheKeepsReportsButNotRecentGaps() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "binnacle-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SalesReportCache(directory: directory)
        let today = Fixtures.day("2026-10-13")

        cache.store(.report("header\nrow"), for: Fixtures.day("2026-10-11"), today: today)
        cache.store(.noSales, for: Fixtures.day("2026-10-12"), today: today)
        cache.store(.noSales, for: Fixtures.day("2026-10-01"), today: today)

        #expect(cache.load(Fixtures.day("2026-10-11")) == .report("header\nrow"))
        #expect(cache.load(Fixtures.day("2026-10-12")) == nil)
        #expect(cache.load(Fixtures.day("2026-10-01")) == .noSales)
    }
}
