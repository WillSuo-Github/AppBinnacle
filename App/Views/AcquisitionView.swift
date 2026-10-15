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
                    MetricTile(
                        title: "First Downloads",
                        value: Int(acquisition.firstDownloads.current).formatted(),
                        change: acquisition.firstDownloads,
                        systemImage: "arrow.down.circle.fill",
                        accentColor: .blue
                    )
                    MetricTile(
                        title: "Redownloads",
                        value: Int(acquisition.redownloads.current).formatted(),
                        change: acquisition.redownloads,
                        systemImage: "arrow.counterclockwise.circle.fill",
                        accentColor: .teal
                    )
                    MetricTile(
                        title: "In-App Purchases",
                        value: Int(acquisition.inAppPurchases.current).formatted(),
                        change: acquisition.inAppPurchases,
                        caption: snapshot.app.sku.isEmpty ? "Set the app’s SKU to include these" : nil,
                        systemImage: "cart.fill",
                        accentColor: .purple
                    )
                    MetricTile(
                        title: "Updates",
                        value: acquisition.updates.formatted(),
                        systemImage: "arrow.triangle.2.circlepath",
                        accentColor: .indigo
                    )
                }

                ChartCard(
                    title: "Downloads per Day",
                    subtitle: range.shortLabel,
                    systemImage: "chart.bar.fill",
                    accentColor: .blue
                ) {
                    Chart {
                        ForEach(sales.days(in: range), id: \.day) { day in
                            BarMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Units", day.firstDownloads))
                                .foregroundStyle(by: .value("Type", "First downloads"))
                            BarMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Units", day.redownloads))
                                .foregroundStyle(by: .value("Type", "Redownloads"))
                        }
                    }
                    .chartForegroundStyleScale([
                        "First downloads": Color.blue,
                        "Redownloads": Color.teal
                    ])
                    .frame(height: 220)
                }

                HStack(alignment: .top, spacing: 14) {
                    ChartCard(
                        title: "Proceeds",
                        subtitle: "By currency of proceeds",
                        systemImage: "dollarsign.circle.fill",
                        accentColor: .green
                    ) {
                        if acquisition.proceeds.isEmpty {
                            VStack(spacing: 6) {
                                Text("No paid sales in this period.")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                                GridRow {
                                    Text("Currency")
                                    Text("This period").gridColumnAlignment(.trailing)
                                    Text("Previous").gridColumnAlignment(.trailing)
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                ForEach(acquisition.proceeds, id: \.currency) { row in
                                    GridRow {
                                        Text(row.currency).fontWeight(.medium)
                                        Text(row.current.formatted(.currency(code: row.currency))).monospacedDigit()
                                        Text(row.previous.formatted(.currency(code: row.currency))).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    ChartCard(
                        title: "Top Countries",
                        subtitle: "First downloads",
                        systemImage: "globe.americas.fill",
                        accentColor: .cyan
                    ) {
                        if acquisition.topCountries.isEmpty {
                            VStack(spacing: 6) {
                                Text("No first downloads in this period.")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            Chart(acquisition.topCountries, id: \.country) { country in
                                BarMark(x: .value("First downloads", country.firstDownloads), y: .value("Country", Self.countryName(country.country)))
                                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                    .cornerRadius(3)
                                    .annotation(position: .trailing) {
                                        Text(country.firstDownloads.formatted()).font(.caption).foregroundStyle(.secondary)
                                    }
                            }
                            .chartXAxis(.hidden)
                            .frame(height: max(120, CGFloat(acquisition.topCountries.count) * 36 + 10))
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
