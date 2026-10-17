import Foundation

enum DisplayCurrency: String, Codable, CaseIterable, Identifiable, Sendable {
    case usd = "USD", cny = "CNY", eur = "EUR", gbp = "GBP", jpy = "JPY"
    case hkd = "HKD", twd = "TWD", cad = "CAD", aud = "AUD", sgd = "SGD"
    case krw = "KRW", chf = "CHF", inr = "INR", brl = "BRL", sek = "SEK", pln = "PLN"

    var id: String { rawValue }
    var title: String {
        let name = Locale.current.localizedString(forCurrencyCode: rawValue) ?? rawValue
        return "\(rawValue) — \(name)"
    }
}

/// One provider's daily USD-based rates, reused for both comparison periods.
struct ExchangeRates: Codable, Equatable, Sendable {
    var updatedAt: Date
    var nextUpdateAt: Date
    var rates: [String: Decimal]

    func isFresh(at now: Date) -> Bool {
        updatedAt <= now && now < nextUpdateAt && now.timeIntervalSince(updatedAt) < 48 * 3600
    }

    func convert(_ amounts: [String: Decimal], to currency: String) -> Decimal? {
        var total: Decimal = 0
        for (source, amount) in amounts.sorted(by: { $0.key < $1.key }) where amount != 0 {
            if source == currency {
                total += amount
            } else {
                guard let sourceRate = rates[source], sourceRate > 0,
                      let targetRate = rates[currency], targetRate > 0 else { return nil }
                total += amount / sourceRate * targetRate
            }
        }
        return total
    }
}

struct ConvertedProceeds: Codable, Equatable, Sendable {
    var currency: String
    var current: Decimal?
    var previous: Decimal?
    var rateDate: Date?
    var missingCurrencies: [String]

    var formattedCurrent: String {
        current.map { $0.formatted(.currency(code: currency)) } ?? "—"
    }

    var formattedPrevious: String {
        previous.map { $0.formatted(.currency(code: currency)) } ?? "—"
    }

    var change: MetricChange? {
        guard let current, let previous else { return nil }
        return MetricChange(current: NSDecimalNumber(decimal: current).doubleValue,
                            previous: NSDecimalNumber(decimal: previous).doubleValue)
    }

    static func make(_ rows: [AppBrief.CurrencyProceeds], currency: String, rates: ExchangeRates?) -> Self {
        var current: [String: Decimal] = [:], previous: [String: Decimal] = [:]
        for row in rows {
            current[row.currency, default: 0] += row.current
            previous[row.currency, default: 0] += row.previous
        }
        // Even offline, zero totals and amounts already in the chosen currency are exact.
        let converter = rates ?? ExchangeRates(updatedAt: .distantPast, nextUpdateAt: .distantPast, rates: [:])
        let missing = Set(rows.filter { row in
            guard row.current != 0 || row.previous != 0, row.currency != currency else { return false }
            return converter.rates[row.currency, default: 0] <= 0 || converter.rates[currency, default: 0] <= 0
        }.map(\.currency)).sorted()
        let needsConversion = rows.contains { $0.currency != currency && ($0.current != 0 || $0.previous != 0) }
        return Self(currency: currency,
                    current: converter.convert(current, to: currency),
                    previous: converter.convert(previous, to: currency),
                    rateDate: needsConversion ? rates?.updatedAt : nil,
                    missingCurrencies: missing)
    }
}

struct ExchangeRateCache: Sendable {
    var fileURL: URL
    static var standard: Self { Self(fileURL: BinnaclePaths.caches.appending(path: "exchange-rates-usd.json")) }

    func load() -> ExchangeRates? {
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? JSONCoding.decoder().decode(ExchangeRates.self, from: data),
              value.rates["USD"] == 1,
              value.rates.values.allSatisfy({ !$0.isNaN && $0 > 0 }),
              value.nextUpdateAt > value.updatedAt else { return nil }
        return value
    }

    func save(_ value: ExchangeRates) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONCoding.encoder().encode(value).write(to: fileURL, options: .atomic)
    }
}

struct ExchangeRateClient: Sendable {
    var transport: any HTTPTransport = URLSessionTransport()

    func latest() async throws -> ExchangeRates {
        let response = try await transport.send(URLRequest(url: URL(string: "https://open.er-api.com/v6/latest/USD")!))
        guard response.isSuccess else {
            throw BinnacleError.http(service: "ExchangeRate-API", status: response.statusCode, message: "Exchange rates could not be updated (HTTP \(response.statusCode)).")
        }
        let payload = try JSONDecoder().decode(Payload.self, from: response.data)
        guard payload.result == "success", payload.base_code == "USD", payload.rates["USD"] == 1,
              payload.rates.values.allSatisfy({ !$0.isNaN && $0 > 0 }),
              payload.time_last_update_unix > 0,
              payload.time_next_update_unix > payload.time_last_update_unix,
              payload.time_last_update_unix <= Date().timeIntervalSince1970 + 300 else {
            throw BinnacleError.invalidResponse(service: "ExchangeRate-API", message: "invalid daily exchange rates")
        }
        return ExchangeRates(updatedAt: Date(timeIntervalSince1970: payload.time_last_update_unix),
                             nextUpdateAt: Date(timeIntervalSince1970: payload.time_next_update_unix), rates: payload.rates)
    }

    private struct Payload: Decodable {
        var result: String
        var base_code: String
        var time_last_update_unix: TimeInterval
        var time_next_update_unix: TimeInterval
        var rates: [String: Decimal]
    }
}
