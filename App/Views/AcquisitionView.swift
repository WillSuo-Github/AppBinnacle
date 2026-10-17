import Charts
import SwiftUI

struct AcquisitionView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief
    @Environment(DashboardModel.self) private var model
    @State private var chartMode = ChartMode.daily

    enum ChartMode: String, CaseIterable, Identifiable {
        case daily = "Daily Units"
        case cumulative = "Cumulative Growth"

        var id: String { rawValue }
    }

    var body: some View {
        if let sales = snapshot.sales, let range = snapshot.salesRange, let acquisition = brief.acquisition {
            let totalFirstDownloads = sales.total(\.firstDownloads, in: range)
            let totalRedownloads = sales.total(\.redownloads, in: range)
            let totalAllInstalls = max(1, totalFirstDownloads + totalRedownloads)
            let redownloadRate = Double(totalRedownloads) / Double(totalAllInstalls)
            let conversionRate = totalFirstDownloads > 0 ? (Double(sales.total(\.inAppPurchases, in: range)) / Double(totalFirstDownloads)) : 0

            DashboardPage {
                HStack(alignment: .center) {
                    if !sales.pendingDays.isEmpty {
                        Label("Reports published through \(sales.throughDay.startDate().formatted(date: .abbreviated, time: .omitted)), covering \(range.shortLabel).",
                              systemImage: "clock")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("App Store Sales & Downloads Report", systemImage: "chart.xyaxis.line")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    #if os(macOS)
                    Button {
                        let filename = "AppBinnacle-Sales-\(snapshot.app.displayName)-\(range.shortLabel).csv"
                        SaveFileDialog.save(filename: filename, content: ReportExporter.exportSalesCSV(snapshot: snapshot))
                    } label: {
                        Label("Export Sales CSV", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Export daily sales and downloads dataset to CSV")
                    #endif
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
                        caption: "\(String(format: "%.1f%%", redownloadRate * 100)) of all installs",
                        systemImage: "arrow.counterclockwise.circle.fill",
                        accentColor: .teal
                    )
                    MetricTile(
                        title: "In-App Purchases",
                        value: Int(acquisition.inAppPurchases.current).formatted(),
                        change: acquisition.inAppPurchases,
                        caption: totalFirstDownloads > 0 ? "\(String(format: "%.1f%%", conversionRate * 100)) conversion" : nil,
                        systemImage: "cart.fill",
                        accentColor: .purple
                    )
                    MetricTile(
                        title: "Updates",
                        value: acquisition.updates.formatted(),
                        caption: "Delivered to devices",
                        systemImage: "arrow.triangle.2.circlepath",
                        accentColor: .indigo
                    )
                }

                ChartCard(
                    title: "Downloads & Acquisition Trend",
                    subtitle: range.shortLabel,
                    systemImage: "chart.bar.fill",
                    accentColor: .blue
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("Chart Mode", selection: $chartMode) {
                                ForEach(ChartMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                            .labelsHidden()

                            Spacer()
                        }

                        let days = sales.days(in: range)

                        switch chartMode {
                        case .daily:
                            Chart {
                                ForEach(days, id: \.day) { day in
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
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: max(1, range.length / 5))) { _ in
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .trailing) { _ in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                        .foregroundStyle(Color.secondary.opacity(0.15))
                                    AxisValueLabel()
                                }
                            }
                            .frame(height: 220)

                        case .cumulative:
                            let cumulativeData = cumulativeSeries(days)
                            Chart {
                                ForEach(cumulativeData, id: \.day) { item in
                                    LineMark(
                                        x: .value("Day", item.day.startDate(), unit: .day),
                                        y: .value("Cumulative installs", item.total)
                                    )
                                    .foregroundStyle(Color.blue)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                    .interpolationMethod(.catmullRom)

                                    AreaMark(
                                        x: .value("Day", item.day.startDate(), unit: .day),
                                        y: .value("Cumulative installs", item.total)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.02)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: max(1, range.length / 5))) { _ in
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .trailing) { _ in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                        .foregroundStyle(Color.secondary.opacity(0.15))
                                    AxisValueLabel()
                                }
                            }
                            .frame(height: 220)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    ChartCard(
                        title: "Total Proceeds",
                        subtitle: "All currencies combined in \(model.displayCurrency.rawValue)",
                        systemImage: "dollarsign.circle.fill",
                        accentColor: .green
                    ) {
                        let total = model.convertedProceeds(acquisition.proceeds)
                        VStack(alignment: .leading, spacing: 14) {
                            Text(total.formattedCurrent)
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            LabeledContent("Previous period", value: total.formattedPrevious)
                                .foregroundStyle(.secondary)
                            if !total.missingCurrencies.isEmpty {
                                Text("Missing exchange rates: \(total.missingCurrencies.joined(separator: ", ")). No partial total is shown.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            CurrencyConversionNote()
                        }
                        .padding(.vertical, 6)
                    }

                    ChartCard(
                        title: "Top Markets & Geography",
                        subtitle: "First downloads by country/territory",
                        systemImage: "globe.americas.fill",
                        accentColor: .cyan
                    ) {
                        if acquisition.topCountries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                                Text("No downloads recorded in this period.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(Array(acquisition.topCountries.prefix(6).enumerated()), id: \.element.country) { index, country in
                                    HStack(spacing: 8) {
                                        Text(Self.flag(for: country.country))
                                            .font(.body)
                                        Text(Self.countryName(country.country))
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)

                                        Spacer()

                                        let share = totalFirstDownloads > 0 ? (Double(country.firstDownloads) / Double(totalFirstDownloads)) : 0
                                        ProgressView(value: share)
                                            .frame(width: 80)
                                            .tint(Color.cyan)

                                        Text(country.firstDownloads.formatted())
                                            .font(.caption.weight(.semibold))
                                            .monospacedDigit()
                                            .frame(width: 40, alignment: .trailing)

                                        Text(String(format: "%.0f%%", share * 100))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 32, alignment: .trailing)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
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

    private func cumulativeSeries(_ days: [SalesDay]) -> [(day: Day, total: Int)] {
        var running = 0
        var result: [(day: Day, total: Int)] = []
        for day in days {
            running += day.firstDownloads
            result.append((day: day.day, total: running))
        }
        return result
    }

    static func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    static func flag(for countryCode: String) -> String {
        let base: UInt32 = 127397
        var s = ""
        for v in countryCode.uppercased().unicodeScalars {
            if let scalar = UnicodeScalar(base + v.value) {
                s.unicodeScalars.append(scalar)
            }
        }
        return s.isEmpty ? "🌐" : s
    }
}
