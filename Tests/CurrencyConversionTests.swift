import Foundation
import Testing

struct CurrencyConversionTests {
    let rates = ExchangeRates(updatedAt: Date(timeIntervalSince1970: 100),
                              nextUpdateAt: Date(timeIntervalSince1970: 200),
                              rates: ["USD": 1, "EUR": Decimal(string: "0.8")!, "CNY": 7, "JPY": 150])

    @Test func combinesCurrenciesAndRefundsWithDecimalPrecision() {
        let rows = [AppBrief.CurrencyProceeds(currency: "USD", current: 5, previous: 10),
                    .init(currency: "EUR", current: 8, previous: 4),
                    .init(currency: "JPY", current: -150, previous: 0)]
        let dollars = ConvertedProceeds.make(rows, currency: "USD", rates: rates)
        #expect(dollars.current == 14)
        #expect(dollars.previous == 15)
        #expect(dollars.rateDate == rates.updatedAt)
        #expect(dollars.missingCurrencies.isEmpty)
        let yuan = ConvertedProceeds.make(rows, currency: "CNY", rates: rates)
        #expect(yuan.current == 98)
        #expect(yuan.previous == 105)
        #expect(yuan.change?.current == 98)
    }

    @Test func neverReportsAPartialTotalWhenARateIsMissing() {
        let rows = [AppBrief.CurrencyProceeds(currency: "USD", current: 10, previous: 5),
                    .init(currency: "XYZ", current: 2, previous: 0)]
        let total = ConvertedProceeds.make(rows, currency: "USD", rates: rates)
        #expect(total.current == nil)
        #expect(total.previous == 5)
        #expect(total.change == nil)
        #expect(total.missingCurrencies == ["XYZ"])
        #expect(total.formattedCurrent == "—")
        #expect(rates.convert(["EUR": 1], to: "XYZ") == nil)
    }

    @Test func handlesZeroAndSameCurrencyWithoutNetwork() {
        #expect(ConvertedProceeds.make([], currency: "CNY", rates: nil).current == 0)
        let total = ConvertedProceeds.make([.init(currency: "CNY", current: 99, previous: -2)], currency: "CNY", rates: nil)
        #expect(total.current == 99)
        #expect(total.previous == -2)
        #expect(total.rateDate == nil)
        #expect(ConvertedProceeds.make([.init(currency: "USD", current: 2, previous: 3)], currency: "CNY", rates: nil).current == nil)
    }

    @Test func portfolioTotalMatchesUnroundedAppTotals() {
        let first = rates.convert(["EUR": Decimal(string: "1.23")!], to: "CNY")!
        let second = rates.convert(["USD": Decimal(string: "4.56")!], to: "CNY")!
        let portfolio = rates.convert(["EUR": Decimal(string: "1.23")!, "USD": Decimal(string: "4.56")!], to: "CNY")
        #expect(portfolio == first + second)
    }

    @Test func cachesRatesAndRecognizesRefreshBoundaries() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "binnacle-fx-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ExchangeRateCache(fileURL: folder.appending(path: "rates.json"))
        #expect(cache.load() == nil)
        try cache.save(rates)
        #expect(cache.load() == rates)
        #expect(rates.isFresh(at: Date(timeIntervalSince1970: 150)))
        #expect(!rates.isFresh(at: Date(timeIntervalSince1970: 200)))
        #expect(!rates.isFresh(at: Date(timeIntervalSince1970: 50)))
        try Data("invalid".utf8).write(to: cache.fileURL)
        #expect(cache.load() == nil)
    }

    @Test func requestsOnlyPublicExchangeRates() async throws {
        let transport = MockTransport { _ in
            .json(#"{"result":"success","base_code":"USD","time_last_update_unix":100,"time_next_update_unix":200,"rates":{"USD":1,"CNY":7.123456,"CLP":950}}"#)
        }
        let actual = try await ExchangeRateClient(transport: transport).latest()
        #expect(actual.rates["CNY"] == Decimal(string: "7.123456"))
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://open.er-api.com/v6/latest/USD")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpBody == nil)
    }

    @Test func rejectsInvalidRatesAndServerErrors() async {
        for payload in [
            #"{"result":"success","base_code":"EUR","time_last_update_unix":100,"time_next_update_unix":200,"rates":{"USD":1}}"#,
            #"{"result":"success","base_code":"USD","time_last_update_unix":100,"time_next_update_unix":200,"rates":{"USD":1,"CNY":0}}"#,
            #"{"result":"success","base_code":"USD","time_last_update_unix":200,"time_next_update_unix":100,"rates":{"USD":1}}"#
        ] {
            let client = ExchangeRateClient(transport: MockTransport { _ in .json(payload) })
            await #expect(throws: BinnacleError.self) { try await client.latest() }
        }
        let client = ExchangeRateClient(transport: MockTransport { _ in .json("{}", status: 429) })
        await #expect(throws: BinnacleError.self) { try await client.latest() }
    }

    @Test func displayCurrencySurvivesConfigurationRoundTripAndOldFiles() throws {
        let old = try JSONDecoder().decode(BinnacleConfiguration.self, from: Data(#"{"apps":[]}"#.utf8))
        #expect(old.displayCurrency == .usd)
        var changed = old
        changed.displayCurrency = .cny
        let decoded = try JSONDecoder().decode(BinnacleConfiguration.self, from: JSONEncoder().encode(changed))
        #expect(decoded.displayCurrency == .cny)
    }
}
