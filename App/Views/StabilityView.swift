import Charts
import SwiftUI

struct StabilityView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief

    var body: some View {
        if let stability = brief.stability {
            DashboardPage {
                MetricGrid {
                    MetricTile(
                        title: "Crash-Free Users",
                        value: Format.rate(stability.crashFreeUsersRate),
                        caption: stability.previousCrashFreeUsersRate.map { "Previous: \(Format.rate($0))" },
                        systemImage: "shield.checkerboard",
                        accentColor: .mint
                    )
                    if let affected = stability.crashAffectedUsers {
                        MetricTile(
                            title: "Crash-Affected Users",
                            value: Int(affected.current).formatted(),
                            change: affected,
                            higherIsBetter: false,
                            systemImage: "exclamationmark.shield.fill",
                            accentColor: .red
                        )
                    }
                    if let issues = stability.openIssues {
                        MetricTile(
                            title: "Open Issues",
                            value: issues.count.formatted(),
                            caption: "Top issues in this period",
                            systemImage: "bolt.heart.fill",
                            accentColor: .orange
                        )
                    }
                }

                if let analytics = snapshot.analytics {
                    let days = analytics.daily(in: snapshot.range).filter { $0.crashFreeUsersRate != nil }
                    if !days.isEmpty {
                        ChartCard(
                            title: "Crash-Free Users per Day",
                            subtitle: "From Google Analytics",
                            systemImage: "shield.checkerboard",
                            accentColor: .mint
                        ) {
                            Chart(days, id: \.day) { day in
                                LineMark(
                                    x: .value("Day", day.day.startDate(), unit: .day),
                                    y: .value("Crash-free users", (day.crashFreeUsersRate ?? 1) * 100)
                                )
                                .foregroundStyle(Color.mint)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.catmullRom)

                                PointMark(
                                    x: .value("Day", day.day.startDate(), unit: .day),
                                    y: .value("Crash-free users", (day.crashFreeUsersRate ?? 1) * 100)
                                )
                                .foregroundStyle(Color.mint)
                                .symbolSize(24)
                            }
                            .chartYScale(domain: yDomain(days))
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: max(1, snapshot.range.length / 5))) { _ in
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                        .foregroundStyle(Color.secondary.opacity(0.15))
                                    AxisValueLabel { Text("\(value.as(Double.self) ?? 0, specifier: "%.1f")%") }
                                }
                            }
                            .frame(height: 220)
                        }
                    }

                    if !analytics.versions.isEmpty {
                        ChartCard(
                            title: "Active Versions",
                            subtitle: "Most active versions in this period",
                            systemImage: "shippingbox.fill",
                            accentColor: .cyan
                        ) {
                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                                GridRow {
                                    Text("Version")
                                    Text("Active users").gridColumnAlignment(.trailing)
                                    Text("Crash-affected").gridColumnAlignment(.trailing)
                                    Text("Crash-free").gridColumnAlignment(.trailing)
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                ForEach(analytics.versions, id: \.version) { version in
                                    GridRow {
                                        Text(version.version).fontWeight(.medium)
                                        Text(version.activeUsers.formatted()).monospacedDigit()
                                        Text(version.crashAffectedUsers.formatted()).monospacedDigit()
                                        Text(Format.rate(version.crashFreeUsersRate))
                                            .monospacedDigit()
                                            .foregroundStyle((version.crashFreeUsersRate ?? 1) < 0.99 ? Color.red : Color.primary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                ChartCard(
                    title: "Open Crashlytics Issues",
                    subtitle: "Sorted by Crashlytics event volume",
                    systemImage: "bolt.heart.fill",
                    accentColor: .orange
                ) {
                    if let issues = stability.openIssues {
                        if issues.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.green)
                                Text("No open issues in this period.")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 80)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(issues) { issue in
                                    IssueRow(issue: issue)
                                    if issue != issues.last { Divider() }
                                }
                            }
                        }
                    } else {
                        let status = snapshot.status(of: .crashlytics)
                        Text(status?.detail ?? "Crashlytics is not connected.")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        } else {
            SourceUnavailableView(status: snapshot.status(of: .googleAnalytics), source: .googleAnalytics)
        }
    }

    private func yDomain(_ days: [AnalyticsDay]) -> ClosedRange<Double> {
        let lowest = days.compactMap(\.crashFreeUsersRate).min() ?? 1
        return max(0, (lowest * 100).rounded(.down) - 0.5)...100
    }
}

private struct IssueRow: View {
    let issue: CrashIssue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.12), in: Capsule())
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.body.weight(.medium)).textSelection(.enabled)
                if !issue.subtitle.isEmpty {
                    Text(issue.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }
                Text("\(issue.events.formatted()) events · \(issue.impactedUsers.formatted()) users")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if let link = issue.consoleURL.flatMap(URL.init(string:)) {
                Link(destination: link) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.body)
                }
                .help("Open in the Firebase console")
            }
        }
    }

    private var label: String {
        switch issue.errorType {
        case "FATAL": return "Crash"
        case "NON_FATAL": return "Non-fatal"
        case "ANR": return "ANR"
        default: return issue.errorType.isEmpty ? "Issue" : issue.errorType
        }
    }

    private var color: Color {
        issue.errorType == "FATAL" ? .red : (issue.errorType == "ANR" ? .orange : .secondary)
    }
}
