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

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Highlights", systemImage: "sparkles")
                        .font(.headline)
                    if brief.highlights.isEmpty {
                        Text("No notable changes compared with the previous \(snapshot.range.length) days.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(brief.highlights, id: \.self) { note in
                            Label(note, systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 12) {
                if let sales = snapshot.sales, let range = snapshot.salesRange {
                    ChartCard(title: "First Downloads", subtitle: range.shortLabel) {
                        Chart(sales.days(in: range), id: \.day) { day in
                            BarMark(x: .value("Day", day.day.startDate(), unit: .day),
                                    y: .value("First downloads", day.firstDownloads))
                        }
                        .frame(height: 180)
                    }
                }
                if let analytics = snapshot.analytics {
                    ChartCard(title: "Daily Active Users", subtitle: snapshot.range.shortLabel) {
                        Chart(analytics.daily(in: snapshot.range), id: \.day) { day in
                            LineMark(x: .value("Day", day.day.startDate(), unit: .day),
                                     y: .value("Active users", day.activeUsers))
                            .interpolationMethod(.monotone)
                            AreaMark(x: .value("Day", day.day.startDate(), unit: .day),
                                     y: .value("Active users", day.activeUsers))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.tint.opacity(0.12))
                        }
                        .frame(height: 180)
                    }
                }
            }

            SourceStatusList(sources: snapshot.sources)

            Text("Updated \(snapshot.generatedAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var downloadsTile: some View {
        if let acquisition = brief.acquisition {
            MetricTile(title: "First Downloads", value: Int(acquisition.firstDownloads.current).formatted(),
                       change: acquisition.firstDownloads,
                       caption: acquisition.period == brief.period ? nil : "Through \(acquisition.period.end.startDate().formatted(date: .abbreviated, time: .omitted))")
        } else {
            unavailableTile("First Downloads", .appStoreSales)
        }
    }

    @ViewBuilder private var proceedsTile: some View {
        if let acquisition = brief.acquisition {
            if let top = acquisition.proceeds.first {
                MetricTile(title: "Proceeds", value: top.current.formatted(.currency(code: top.currency)),
                           change: MetricChange(current: top.current.doubleValue, previous: top.previous.doubleValue),
                           caption: acquisition.proceeds.count > 1 ? "+ \(acquisition.proceeds.count - 1) more currencies" : nil)
            } else {
                MetricTile(title: "Proceeds", value: "None", caption: "No paid sales in this period")
            }
        } else {
            unavailableTile("Proceeds", .appStoreSales)
        }
    }

    @ViewBuilder private var activeUsersTile: some View {
        if let engagement = brief.engagement {
            MetricTile(title: "Active Users", value: Int(engagement.activeUsers.current).formatted(), change: engagement.activeUsers,
                       caption: "\(Int(engagement.averageDailyActiveUsers.rounded()).formatted()) per day on average")
        } else {
            unavailableTile("Active Users", .googleAnalytics)
        }
    }

    @ViewBuilder private var stabilityTile: some View {
        if let stability = brief.stability, let rate = stability.crashFreeUsersRate {
            MetricTile(title: "Crash-Free Users", value: Format.rate(rate),
                       caption: stability.previousCrashFreeUsersRate.map { "Previous: \(Format.rate($0))" })
        } else if let issues = brief.stability?.openIssues {
            MetricTile(title: "Open Crash Issues", value: issues.count.formatted(), caption: "Crashlytics")
        } else {
            unavailableTile("Crash-Free Users", .googleAnalytics)
        }
    }

    @ViewBuilder private var reviewsTile: some View {
        if let reviews = brief.reviews {
            MetricTile(title: "New Reviews", value: reviews.count.formatted(),
                       change: MetricChange(reviews.count, reviews.previousCount),
                       caption: reviews.averageRating.map { "Average \(Format.number($0))★ · \(reviews.lowRatingCount) rated 1–2★" })
        } else {
            unavailableTile("New Reviews", .appStoreReviews)
        }
    }

    private func unavailableTile(_ title: String, _ source: DataSource) -> some View {
        let status = snapshot.status(of: source)
        return MetricTile(title: title, value: "—",
                          caption: status?.state == .failed ? "\(source.title) didn’t load" : "Connect \(source.title)")
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            configuration.title
        }
    }
}
