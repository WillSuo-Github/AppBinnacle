import Charts
import SwiftUI

struct OverviewView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief

    var body: some View {
        DashboardPage {
            MetricGrid {
                downloadsTile
                proceedsTile
                activeUsersTile
                stabilityTile
                reviewsTile
            }

            HighlightsCard(highlights: brief.highlights, periodLength: snapshot.range.length)

            HStack(alignment: .top, spacing: 14) {
                if let sales = snapshot.sales, let range = snapshot.salesRange {
                    ChartCard(
                        title: "First Downloads",
                        subtitle: range.shortLabel,
                        systemImage: "arrow.down.circle.fill",
                        accentColor: .blue
                    ) {
                        let days = sales.days(in: range)
                        let totalDownloads = days.reduce(0) { $0 + $1.firstDownloads }

                        if totalDownloads == 0 {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.title2)
                                    .foregroundStyle(.tertiary)
                                Text("0 First Downloads Recorded")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text("No new installations reported by App Store Connect in this period.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            Chart(days, id: \.day) { day in
                                BarMark(
                                    x: .value("Day", day.day.startDate(), unit: .day),
                                    y: .value("First downloads", day.firstDownloads)
                                )
                                .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom))
                                .cornerRadius(3)
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
                            .frame(height: 180)
                        }
                    }
                }

                if let analytics = snapshot.analytics {
                    ChartCard(
                        title: "Daily Active Users",
                        subtitle: snapshot.range.shortLabel,
                        systemImage: "person.2.fill",
                        accentColor: .indigo
                    ) {
                        let daily = analytics.daily(in: snapshot.range)
                        Chart(daily, id: \.day) { day in
                            LineMark(
                                x: .value("Day", day.day.startDate(), unit: .day),
                                y: .value("Active users", day.activeUsers)
                            )
                            .foregroundStyle(Color.indigo)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Day", day.day.startDate(), unit: .day),
                                y: .value("Active users", day.activeUsers)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.indigo.opacity(0.32), Color.indigo.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: max(1, snapshot.range.length / 5))) { _ in
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
                        .frame(height: 180)
                    }
                }
            }

            SourceStatusList(sources: snapshot.sources, updatedAt: snapshot.generatedAt)
        }
    }

    @ViewBuilder private var downloadsTile: some View {
        if let acquisition = brief.acquisition {
            MetricTile(
                title: "First Downloads",
                value: Int(acquisition.firstDownloads.current).formatted(),
                change: acquisition.firstDownloads,
                caption: acquisition.period == brief.period ? nil : "Through \(acquisition.period.end.startDate().formatted(date: .abbreviated, time: .omitted))",
                systemImage: "arrow.down.circle.fill",
                accentColor: .blue
            )
        } else {
            unavailableTile("First Downloads", .appStoreSales, systemImage: "arrow.down.circle.fill", accentColor: .blue)
        }
    }

    @ViewBuilder private var proceedsTile: some View {
        if let acquisition = brief.acquisition {
            if let top = acquisition.proceeds.first {
                MetricTile(
                    title: "Proceeds",
                    value: top.current.formatted(.currency(code: top.currency)),
                    change: MetricChange(current: top.current.doubleValue, previous: top.previous.doubleValue),
                    caption: acquisition.proceeds.count > 1 ? "+ \(acquisition.proceeds.count - 1) more currencies" : nil,
                    systemImage: "dollarsign.circle.fill",
                    accentColor: .green
                )
            } else {
                MetricTile(
                    title: "Proceeds",
                    value: "None",
                    caption: "No paid sales in this period",
                    systemImage: "dollarsign.circle.fill",
                    accentColor: .green
                )
            }
        } else {
            unavailableTile("Proceeds", .appStoreSales, systemImage: "dollarsign.circle.fill", accentColor: .green)
        }
    }

    @ViewBuilder private var activeUsersTile: some View {
        if let engagement = brief.engagement {
            MetricTile(
                title: "Active Users",
                value: Int(engagement.activeUsers.current).formatted(),
                change: engagement.activeUsers,
                caption: "\(Int(engagement.averageDailyActiveUsers.rounded()).formatted()) per day on average",
                systemImage: "person.2.fill",
                accentColor: .indigo
            )
        } else {
            unavailableTile("Active Users", .googleAnalytics, systemImage: "person.2.fill", accentColor: .indigo)
        }
    }

    @ViewBuilder private var stabilityTile: some View {
        if let stability = brief.stability, let rate = stability.crashFreeUsersRate {
            MetricTile(
                title: "Crash-Free Users",
                value: Format.rate(rate),
                caption: stability.previousCrashFreeUsersRate.map { "Previous: \(Format.rate($0))" },
                systemImage: "shield.checkerboard",
                accentColor: .mint
            )
        } else if let issues = brief.stability?.openIssues {
            MetricTile(
                title: "Open Crash Issues",
                value: issues.count.formatted(),
                caption: "Crashlytics",
                systemImage: "bolt.heart.fill",
                accentColor: .pink
            )
        } else {
            unavailableTile("Crash-Free Users", .googleAnalytics, systemImage: "shield.checkerboard", accentColor: .mint)
        }
    }

    @ViewBuilder private var reviewsTile: some View {
        if let reviews = brief.reviews {
            MetricTile(
                title: "New Reviews",
                value: reviews.count.formatted(),
                change: MetricChange(reviews.count, reviews.previousCount),
                caption: reviews.averageRating.map { "Average \(Format.number($0))★ · \(reviews.lowRatingCount) rated 1–2★" },
                systemImage: "star.bubble.fill",
                accentColor: .orange
            )
        } else {
            unavailableTile("New Reviews", .appStoreReviews, systemImage: "star.bubble.fill", accentColor: .orange)
        }
    }

    private func unavailableTile(_ title: String, _ source: DataSource, systemImage: String, accentColor: Color) -> some View {
        let status = snapshot.status(of: source)
        return MetricTile(
            title: title,
            value: "—",
            caption: status?.state == .failed ? "\(source.title) didn’t load" : "Connect \(source.title)",
            systemImage: systemImage,
            accentColor: accentColor
        )
    }
}

struct HighlightsCard: View {
    let highlights: [String]
    let periodLength: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text("Highlights & Insights")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }

            if highlights.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                    Text("All metrics remained stable with no anomalous drops or spikes over the past \(periodLength) days.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(highlights, id: \.self) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                            Text(note)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appleCard(cornerRadius: 12)
    }
}
