import Charts
import SwiftUI

struct AcquisitionView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief

    var body: some View {
        if let sales = snapshot.sales, let range = snapshot.salesRange, let acquisition = brief.acquisition {
            DashboardPage {
                if !sales.pendingDays.isEmpty {
                    Label("Apple hasn’t published reports after \(sales.throughDay.startDate().formatted(date: .abbreviated, time: .omitted)) yet, so this page covers \(range.shortLabel).",
                          systemImage: "clock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                MetricGrid {
                    MetricTile(title: "First Downloads", value: Int(acquisition.firstDownloads.current).formatted(), change: acquisition.firstDownloads)
                    MetricTile(title: "Redownloads", value: Int(acquisition.redownloads.current).formatted(), change: acquisition.redownloads)
                    MetricTile(title: "In-App Purchases", value: Int(acquisition.inAppPurchases.current).formatted(), change: acquisition.inAppPurchases,
                               caption: snapshot.app.sku.isEmpty ? "Set the app’s SKU to include these" : nil)
                    MetricTile(title: "Updates", value: acquisition.updates.formatted())
                }

                ChartCard(title: "Downloads per Day", subtitle: range.shortLabel) {
                    Chart {
                        ForEach(sales.days(in: range), id: \.day) { day in
                            BarMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Units", day.firstDownloads))
                                .foregroundStyle(by: .value("Type", "First downloads"))
                            BarMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Units", day.redownloads))
                                .foregroundStyle(by: .value("Type", "Redownloads"))
                        }
                    }
                    .frame(height: 220)
                }

                HStack(alignment: .top, spacing: 12) {
                    ChartCard(title: "Proceeds", subtitle: "By currency of proceeds") {
                        if acquisition.proceeds.isEmpty {
                            Text("No paid sales in this period.").foregroundStyle(.secondary)
                        } else {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                GridRow {
                                    Text("Currency")
                                    Text("This period").gridColumnAlignment(.trailing)
                                    Text("Previous").gridColumnAlignment(.trailing)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                ForEach(acquisition.proceeds, id: \.currency) { row in
                                    GridRow {
                                        Text(row.currency)
                                        Text(row.current.formatted(.currency(code: row.currency))).monospacedDigit()
                                        Text(row.previous.formatted(.currency(code: row.currency))).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    ChartCard(title: "Top Countries", subtitle: "First downloads") {
                        if acquisition.topCountries.isEmpty {
                            Text("No first downloads in this period.").foregroundStyle(.secondary)
                        } else {
                            Chart(acquisition.topCountries, id: \.country) { country in
                                BarMark(x: .value("First downloads", country.firstDownloads), y: .value("Country", Self.countryName(country.country)))
                                    .annotation(position: .trailing) {
                                        Text(country.firstDownloads.formatted()).font(.caption).foregroundStyle(.secondary)
                                    }
                            }
                            .chartXAxis(.hidden)
                            .frame(height: CGFloat(acquisition.topCountries.count) * 36 + 10)
                        }
                    }
                }

                if !acquisition.unclassifiedProductTypes.isEmpty {
                    Label("Not counted above: " + acquisition.unclassifiedProductTypes.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ") + ". These product types aren’t classified yet.",
                          systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            SourceUnavailableView(status: snapshot.status(of: .appStoreSales), source: .appStoreSales)
        }
    }

    static func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
