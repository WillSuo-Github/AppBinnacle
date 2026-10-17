import SwiftUI

struct CurrencyConversionNote: View {
    @Environment(DashboardModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Estimated proceeds in \(model.displayCurrency.rawValue)")
                if let rates = model.exchangeRates {
                    Text("· FX \(rates.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                    if !rates.isFresh(at: Date()) { Text("· Cached rates") }
                } else {
                    Text(model.isLoadingExchangeRates ? "· Loading rates…" : "· Rates unavailable")
                }
                Spacer(minLength: 0)
                Link("Rates by ExchangeRate-API", destination: URL(string: "https://www.exchangerate-api.com")!)
            }
            Text("Both periods use the same daily rates. Estimates may differ from App Store Connect and final payouts.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
