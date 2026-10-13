import Foundation

/// How AppBinnacle counts a sales report row, based on Apple's Product Type Identifier.
/// Codes that are not listed are reported as "other" instead of being guessed.
enum SalesCategory: String, Codable, CaseIterable, Sendable {
    case firstDownload
    case redownload
    case update
    case inAppPurchase
    case other

    init(productType: String) {
        switch productType.trimmed.uppercased() {
        case "1", "1F", "1T", "F1": self = .firstDownload
        case "3", "3F": self = .redownload
        case "7", "7F", "7T", "F7": self = .update
        case "IA1", "IA9", "IAY", "FI1": self = .inAppPurchase
        default: self = .other
        }
    }

    var title: String {
        switch self {
        case .firstDownload: return "First downloads"
        case .redownload: return "Redownloads"
        case .update: return "Updates"
        case .inAppPurchase: return "In-app purchases"
        case .other: return "Other"
        }
    }
}

struct SalesReportRow: Equatable, Sendable {
    var sku: String
    var title: String
    var productType: String
    var units: Int
    /// Proceeds per unit, in proceedsCurrency.
    var developerProceeds: Decimal
    var proceedsCurrency: String
    var countryCode: String
    var appleIdentifier: String
    var parentIdentifier: String

    var category: SalesCategory { SalesCategory(productType: productType) }
}

enum SalesReportParser {
    static func parse(_ text: String) throws -> [SalesReportRow] {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let headerLine = lines.first else { return [] }
        let header = headerLine.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmed }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }

        guard let typeColumn = column("Product Type Identifier"),
              let unitsColumn = column("Units"),
              let appleIDColumn = column("Apple Identifier")
        else {
            throw BinnacleError.invalidResponse(
                service: AppStoreConnectClient.serviceName,
                message: "the sales report is missing the Product Type Identifier, Units, or Apple Identifier column")
        }
        let skuColumn = column("SKU"), titleColumn = column("Title")
        let proceedsColumn = column("Developer Proceeds"), currencyColumn = column("Currency of Proceeds")
        let countryColumn = column("Country Code"), parentColumn = column("Parent Identifier")
        let posix = Locale(identifier: "en_US_POSIX")

        return lines.dropFirst().compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            func field(_ index: Int?) -> String {
                guard let index, index < fields.count else { return "" }
                return fields[index].trimmed
            }
            let unitsText = field(unitsColumn)
            guard let units = Int(unitsText) ?? Double(unitsText).map({ Int($0.rounded()) }) else { return nil }
            return SalesReportRow(
                sku: field(skuColumn),
                title: field(titleColumn),
                productType: field(typeColumn),
                units: units,
                developerProceeds: Decimal(string: field(proceedsColumn), locale: posix) ?? 0,
                proceedsCurrency: field(currencyColumn),
                countryCode: field(countryColumn),
                appleIdentifier: field(appleIDColumn),
                parentIdentifier: field(parentColumn))
        }
    }
}

/// One app's App Store activity on one day.
struct SalesDay: Codable, Equatable, Sendable {
    var day: Day
    var firstDownloads = 0
    var redownloads = 0
    var updates = 0
    var inAppPurchases = 0
    var otherUnits = 0
    /// Developer proceeds by currency of proceeds.
    var proceeds: [String: Decimal] = [:]
    var firstDownloadsByCountry: [String: Int] = [:]
    /// Units of product types AppBinnacle does not classify, keyed by product type.
    var otherProductTypes: [String: Int] = [:]

    init(day: Day) {
        self.day = day
    }
}

struct SalesSeries: Codable, Equatable, Sendable {
    /// Days in ascending order, ending at throughDay.
    var days: [SalesDay]
    /// The latest day with a published report.
    var throughDay: Day
    /// Requested days whose reports Apple has not published yet.
    var pendingDays: [Day]

    func days(in range: DayRange) -> [SalesDay] {
        days.filter { range.contains($0.day) }
    }

    func total(_ value: KeyPath<SalesDay, Int>, in range: DayRange) -> Int {
        days(in: range).reduce(0) { $0 + $1[keyPath: value] }
    }

    func proceeds(in range: DayRange) -> [String: Decimal] {
        days(in: range).reduce(into: [:]) { result, day in
            for (currency, amount) in day.proceeds { result[currency, default: 0] += amount }
        }
    }

    func firstDownloadsByCountry(in range: DayRange) -> [String: Int] {
        days(in: range).reduce(into: [:]) { result, day in
            for (country, units) in day.firstDownloadsByCountry { result[country, default: 0] += units }
        }
    }

    func otherProductTypes(in range: DayRange) -> [String: Int] {
        days(in: range).reduce(into: [:]) { result, day in
            for (type, units) in day.otherProductTypes { result[type, default: 0] += units }
        }
    }
}

enum ParsedSalesReport: Equatable, Sendable {
    case rows([SalesReportRow])
    case noSales
}

enum SalesAggregator {
    /// App rows match the app's Apple ID; in-app purchase rows name the app's SKU as their parent.
    static func belongs(_ row: SalesReportRow, to app: TrackedApp) -> Bool {
        if row.appleIdentifier == app.appleID { return true }
        let sku = app.sku.trimmed
        return !sku.isEmpty && row.parentIdentifier == sku
    }

    static func summarize(_ rows: [SalesReportRow], day: Day, app: TrackedApp) -> SalesDay {
        var summary = SalesDay(day: day)
        for row in rows where belongs(row, to: app) {
            switch row.category {
            case .firstDownload:
                summary.firstDownloads += row.units
                if !row.countryCode.isEmpty {
                    summary.firstDownloadsByCountry[row.countryCode, default: 0] += row.units
                }
            case .redownload:
                summary.redownloads += row.units
            case .update:
                summary.updates += row.units
            case .inAppPurchase:
                summary.inAppPurchases += row.units
            case .other:
                summary.otherUnits += row.units
                summary.otherProductTypes[row.productType.isEmpty ? "unknown" : row.productType, default: 0] += row.units
            }
            let amount = Decimal(row.units) * row.developerProceeds
            if amount != 0, !row.proceedsCurrency.isEmpty {
                summary.proceeds[row.proceedsCurrency, default: 0] += amount
            }
        }
        return summary
    }

    /// Builds the app's series. Missing reports for the last two days are treated as "not published yet",
    /// so the series ends at the latest published day instead of counting those days as zero.
    static func series(app: TrackedApp, reports: [Day: ParsedSalesReport], fetched: DayRange,
                       requestedEnd: Day, today: Day) -> SalesSeries {
        var through = min(requestedEnd, fetched.end)
        var pending: [Day] = []
        while through > fetched.start, through.distance(to: today) <= 2, reports[through] ?? .noSales == .noSales {
            pending.append(through)
            through = through.adding(days: -1)
        }
        let days = DayRange(start: fetched.start, end: through).days.map { day -> SalesDay in
            guard case .rows(let rows)? = reports[day] else { return SalesDay(day: day) }
            return summarize(rows, day: day, app: app)
        }
        return SalesSeries(days: days, throughDay: through, pendingDays: pending.sorted())
    }
}

/// Published daily reports never change, so they are cached on disk per vendor and day.
struct SalesReportCache: Sendable {
    var directory: URL

    static func standard(vendorNumber: String) -> SalesReportCache {
        let folder = vendorNumber.filter { $0.isLetter || $0.isNumber }
        return SalesReportCache(directory: BinnaclePaths.caches.appending(path: "sales-reports/\(folder.isEmpty ? "default" : folder)"))
    }

    func load(_ day: Day) -> SalesReportResponse? {
        if FileManager.default.fileExists(atPath: file(day, "none").path(percentEncoded: false)) { return .noSales }
        guard let data = try? Data(contentsOf: file(day, "tsv")) else { return nil }
        return .report(String(decoding: data, as: UTF8.self))
    }

    /// "No sales" answers for recent days are not cached because Apple may still publish the report.
    func store(_ response: SalesReportResponse, for day: Day, today: Day) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            switch response {
            case .report(let text):
                try Data(text.utf8).write(to: file(day, "tsv"), options: .atomic)
            case .noSales where day.distance(to: today) > 3:
                try Data().write(to: file(day, "none"), options: .atomic)
            case .noSales:
                break
            }
        } catch {
            // The cache only saves requests; failing to write it is not an error for the caller.
        }
    }

    private func file(_ day: Day, _ suffix: String) -> URL {
        directory.appending(path: "\(day.iso).\(suffix)")
    }
}

struct SalesReportLoader: Sendable {
    var client: AppStoreConnectClient
    var vendorNumber: String
    var cache: SalesReportCache?
    var maxConcurrentRequests = 6

    func load(days: [Day], today: Day) async throws -> [Day: SalesReportResponse] {
        var results: [Day: SalesReportResponse] = [:]
        var missing: [Day] = []
        for day in days {
            if let cached = cache?.load(day) { results[day] = cached } else { missing.append(day) }
        }
        let client = client, vendorNumber = vendorNumber, cache = cache
        let fetched = try await withThrowingTaskGroup(of: (Day, SalesReportResponse).self) { group in
            var collected: [Day: SalesReportResponse] = [:]
            var queue = missing.makeIterator()
            for _ in 0..<maxConcurrentRequests {
                guard let day = queue.next() else { break }
                group.addTask { (day, try await client.dailySalesReport(vendorNumber: vendorNumber, day: day)) }
            }
            while let (day, response) = try await group.next() {
                collected[day] = response
                cache?.store(response, for: day, today: today)
                if let next = queue.next() {
                    group.addTask { (next, try await client.dailySalesReport(vendorNumber: vendorNumber, day: next)) }
                }
            }
            return collected
        }
        results.merge(fetched) { _, new in new }
        return results
    }
}
