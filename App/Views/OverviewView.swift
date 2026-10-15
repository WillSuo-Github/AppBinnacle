import Charts
import SwiftUI

struct OverviewView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief
    @Environment(DashboardModel.self) private var model

    var body: some View {
        DashboardPage {
            MetricGrid {
                downloadsTile
                proceedsTile
                activeUsersTile
                stabilityTile
                reviewsTile
            }

            if model.isAllApps && !model.configuration.apps.isEmpty {
                PortfolioMatrixCard(
                    snapshots: model.loadedSnapshots,
                    apps: model.configuration.apps
                ) { appleID in
                    model.selectedAppID = appleID
                }
            }

            HighlightsCard(highlights: brief.highlights, periodLength: snapshot.range.length)

            HStack(alignment: .top, spacing: 14) {
                if let sales = snapshot.sales, let range = snapshot.salesRange {
                    ChartCard(
                        title: model.isAllApps ? "Total First Downloads" : "First Downloads",
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
                        title: model.isAllApps ? "Total Daily Active Users" : "Daily Active Users",
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
                title: model.isAllApps ? "Total Downloads" : "First Downloads",
                value: Int(acquisition.firstDownloads.current).formatted(),
                change: acquisition.firstDownloads,
                caption: acquisition.period == brief.period ? nil : "Through \(acquisition.period.end.startDate().formatted(date: .abbreviated, time: .omitted))",
                systemImage: "arrow.down.circle.fill",
                accentColor: .blue
            )
        } else {
            unavailableTile(model.isAllApps ? "Total Downloads" : "First Downloads", .appStoreSales, systemImage: "arrow.down.circle.fill", accentColor: .blue)
        }
    }

    @ViewBuilder private var proceedsTile: some View {
        if let acquisition = brief.acquisition {
            if let top = acquisition.proceeds.first {
                MetricTile(
                    title: model.isAllApps ? "Total Proceeds" : "Proceeds",
                    value: top.current.formatted(.currency(code: top.currency)),
                    change: MetricChange(current: top.current.doubleValue, previous: top.previous.doubleValue),
                    caption: acquisition.proceeds.count > 1 ? "+ \(acquisition.proceeds.count - 1) more currencies" : nil,
                    systemImage: "dollarsign.circle.fill",
                    accentColor: .green
                )
            } else {
                MetricTile(
                    title: model.isAllApps ? "Total Proceeds" : "Proceeds",
                    value: "None",
                    caption: "No paid sales in this period",
                    systemImage: "dollarsign.circle.fill",
                    accentColor: .green
                )
            }
        } else {
            unavailableTile(model.isAllApps ? "Total Proceeds" : "Proceeds", .appStoreSales, systemImage: "dollarsign.circle.fill", accentColor: .green)
        }
    }

    @ViewBuilder private var activeUsersTile: some View {
        if let engagement = brief.engagement {
            MetricTile(
                title: model.isAllApps ? "Total Active Users" : "Active Users",
                value: Int(engagement.activeUsers.current).formatted(),
                change: engagement.activeUsers,
                caption: "\(Int(engagement.averageDailyActiveUsers.rounded()).formatted())/day avg",
                systemImage: "person.2.fill",
                accentColor: .indigo
            )
        } else {
            unavailableTile(model.isAllApps ? "Total Active Users" : "Active Users", .googleAnalytics, systemImage: "person.2.fill", accentColor: .indigo)
        }
    }

    @ViewBuilder private var stabilityTile: some View {
        if let stability = brief.stability, let rate = stability.crashFreeUsersRate {
            MetricTile(
                title: model.isAllApps ? "Avg Crash-Free" : "Crash-Free Users",
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
            unavailableTile(model.isAllApps ? "Avg Crash-Free" : "Crash-Free Users", .googleAnalytics, systemImage: "shield.checkerboard", accentColor: .mint)
        }
    }

    @ViewBuilder private var reviewsTile: some View {
        if let reviews = brief.reviews {
            MetricTile(
                title: model.isAllApps ? "Total Reviews" : "New Reviews",
                value: reviews.count.formatted(),
                change: MetricChange(reviews.count, reviews.previousCount),
                caption: reviews.averageRating.map { "Average \(Format.number($0))★ · \(reviews.lowRatingCount) rated 1–2★" },
                systemImage: "star.bubble.fill",
                accentColor: .orange
            )
        } else {
            unavailableTile(model.isAllApps ? "Total Reviews" : "New Reviews", .appStoreReviews, systemImage: "star.bubble.fill", accentColor: .orange)
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

struct PortfolioMatrixCard: View {
    let snapshots: [DashboardSnapshot]
    let apps: [TrackedApp]
    let onSelectApp: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text("All Products Matrix (\(apps.count))")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Text("Click any app to view its dedicated dashboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(apps) { app in
                    let snap = snapshots.first { $0.app.appleID == app.appleID }
                    AppPortfolioRow(app: app, snapshot: snap) {
                        onSelectApp(app.appleID)
                    }
                    if app.appleID != apps.last?.appleID {
                        Divider()
                            .opacity(0.5)
                    }
                }
            }
        }
        .padding(16)
        .appleCard(cornerRadius: 14)
    }
}

struct AppPortfolioRow: View {
    let app: TrackedApp
    let snapshot: DashboardSnapshot?
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // App glyph
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [.blue.opacity(0.85), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(app.bundleID.isEmpty ? "Apple ID: \(app.appleID)" : app.bundleID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 150, alignment: .leading)

                Spacer(minLength: 8)

                // First Downloads
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Downloads")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    let dls = snapshot?.sales?.total(\.firstDownloads, in: snapshot?.salesRange ?? snapshot?.range ?? DayRange(ending: Day.yesterday(), length: 7)) ?? 0
                    Text(dls.formatted())
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(dls > 0 ? Color.primary : Color.secondary)
                }
                .frame(width: 75, alignment: .trailing)

                // Proceeds
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Proceeds")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    let proceeds = snapshot?.sales?.proceeds(in: snapshot?.salesRange ?? snapshot?.range ?? DayRange(ending: Day.yesterday(), length: 7)) ?? [:]
                    let top = proceeds.first
                    Text(top != nil ? top!.value.formatted(.currency(code: top!.key)) : "$0.00")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(top != nil && top!.value > 0 ? Color.green : Color.secondary)
                }
                .frame(width: 85, alignment: .trailing)

                // Active Users (GA4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Active Users")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    let users = snapshot?.analytics?.current.activeUsers ?? 0
                    Text(snapshot?.analytics != nil ? users.formatted() : "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(users > 0 ? Color.indigo : Color.secondary)
                }
                .frame(width: 80, alignment: .trailing)

                // Stability
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Crash-Free")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let rate = snapshot?.analytics?.current.crashFreeUsersRate {
                        Text(Format.rate(rate))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(rate >= 0.99 ? Color.mint : Color.red)
                    } else {
                        Text("—")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 75, alignment: .trailing)

                // Reviews
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Reviews")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    let reviewCount = snapshot?.reviews?.count ?? 0
                    Text(reviewCount.formatted())
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(reviewCount > 0 ? Color.orange : Color.secondary)
                }
                .frame(width: 60, alignment: .trailing)

                // Navigation action arrow
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
