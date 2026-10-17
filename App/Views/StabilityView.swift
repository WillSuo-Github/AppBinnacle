import Charts
import SwiftUI

struct StabilityView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief
    @State private var issueFilter = IssueFilter.all

    enum IssueFilter: String, CaseIterable, Identifiable {
        case all = "All Issues"
        case fatal = "Fatal Crashes"
        case nonFatal = "Non-Fatal"
        case anr = "ANRs"

        var id: String { rawValue }

        func matches(_ errorType: String) -> Bool {
            switch self {
            case .all: return true
            case .fatal: return errorType == "FATAL"
            case .nonFatal: return errorType == "NON_FATAL"
            case .anr: return errorType == "ANR"
            }
        }
    }

    var body: some View {
        if let stability = brief.stability {
            DashboardPage {
                HStack(alignment: .center) {
                    Label("Application Health & Crash Diagnostics", systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    #if os(macOS)
                    Button {
                        let filename = "AppBinnacle-Stability-\(snapshot.app.displayName)-\(snapshot.range.shortLabel).csv"
                        SaveFileDialog.save(filename: filename, content: ReportExporter.exportStabilityCSV(snapshot: snapshot))
                    } label: {
                        Label("Export Stability CSV", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Export stability metrics and crash reports to CSV")
                    #endif
                }

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
                        let fatalCount = issues.filter { $0.errorType == "FATAL" }.count
                        MetricTile(
                            title: "Open Issues",
                            value: issues.count.formatted(),
                            caption: "\(fatalCount) fatal crashes",
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
                            subtitle: "From Google Analytics telemetry",
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
                        let totalVersionActive = max(1, analytics.versions.reduce(0) { $0 + $1.activeUsers })
                        ChartCard(
                            title: "Version Adoption & Stability Health",
                            subtitle: "Active versions distribution and crash-free comparison",
                            systemImage: "shippingbox.fill",
                            accentColor: .cyan
                        ) {
                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                                GridRow {
                                    Text("Version")
                                    Text("Active Users").gridColumnAlignment(.trailing)
                                    Text("Adoption Share").gridColumnAlignment(.trailing)
                                    Text("Crash-Affected").gridColumnAlignment(.trailing)
                                    Text("Crash-Free Rate").gridColumnAlignment(.trailing)
                                    Text("Health Status").gridColumnAlignment(.trailing)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                                ForEach(analytics.versions, id: \.version) { version in
                                    let share = Double(version.activeUsers) / Double(totalVersionActive)
                                    let rate = version.crashFreeUsersRate ?? 1.0

                                    GridRow {
                                        Text(version.version).fontWeight(.semibold)
                                        Text(version.activeUsers.formatted()).monospacedDigit()
                                        HStack(spacing: 6) {
                                            ProgressView(value: share)
                                                .frame(width: 50)
                                                .tint(Color.cyan)
                                            Text(String(format: "%.0f%%", share * 100))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        Text(version.crashAffectedUsers.formatted()).monospacedDigit()
                                        Text(Format.rate(version.crashFreeUsersRate))
                                            .monospacedDigit()
                                            .foregroundStyle(rate < 0.99 ? Color.red : Color.primary)
                                        healthBadge(rate)
                                    }
                                    .contextMenu {
                                        CopyMenuItem(title: "Copy Version", text: version.version)
                                        CopyMenuItem(
                                            title: "Copy Version Metrics",
                                            text: "Version: \(version.version)\nActive users: \(version.activeUsers)\nAdoption: \(String(format: "%.1f%%", share * 100))\nCrash-affected: \(version.crashAffectedUsers)\nCrash-free: \(Format.rate(version.crashFreeUsersRate))"
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                ChartCard(
                    title: "Open Crashlytics Issues",
                    subtitle: "Filtered by issue severity and frequency",
                    systemImage: "bolt.heart.fill",
                    accentColor: .orange
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("Issue Filter", selection: $issueFilter) {
                                ForEach(IssueFilter.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                            .labelsHidden()

                            Spacer()
                        }

                        if let issues = stability.openIssues {
                            let filtered = issues.filter { issueFilter.matches($0.errorType) }

                            if filtered.isEmpty {
                                VStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.green)
                                    Text(issues.isEmpty ? "No open crash issues in this period." : "No issues match the selected filter.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 80)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(filtered) { issue in
                                        IssueRow(issue: issue)
                                        if issue.id != filtered.last?.id { Divider().opacity(0.5) }
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
            }
            .contextMenu {
                Picker("Issue Filter", selection: $issueFilter) {
                    ForEach(IssueFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                Divider()
                ReportMenuItems(context: DashboardReportContext(snapshot: snapshot, section: .stability))
            }
        } else {
            SourceUnavailableView(status: snapshot.status(of: .googleAnalytics), source: .googleAnalytics)
        }
    }

    @ViewBuilder
    private func healthBadge(_ rate: Double) -> some View {
        if rate >= 0.995 {
            Text("Healthy")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.green)
        } else if rate >= 0.98 {
            Text("Monitor")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.orange)
        } else {
            Text("High Risk")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.red)
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
        .contentShape(Rectangle())
        .contextMenu {
            if let link = issue.consoleURL.flatMap(URL.init(string:)) {
                Link(destination: link) {
                    Label("Open in Firebase Console", systemImage: "arrow.up.forward.square")
                }
                CopyMenuItem(title: "Copy Console Link", text: link.absoluteString)
                Divider()
            }
            CopyMenuItem(title: "Copy Issue Details", text: "\(issue.title)\n\(issue.subtitle)\n\(issue.errorType) · \(issue.events) events · \(issue.impactedUsers) users\nID: \(issue.id)")
            CopyMenuItem(title: "Copy Issue ID", text: issue.id)
            CopyMenuItem(title: "Copy Issue Title", text: issue.title)
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
