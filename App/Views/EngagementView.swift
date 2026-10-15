import Charts
import SwiftUI

struct EngagementView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief
    @State private var chartMode = EngagementChartMode.activeUsers

    enum EngagementChartMode: String, CaseIterable, Identifiable {
        case activeUsers = "Active Users"
        case sessions = "Sessions & Frequency"

        var id: String { rawValue }
    }

    var body: some View {
        if let analytics = snapshot.analytics, let engagement = brief.engagement {
            let current = analytics.daily(in: snapshot.range)
            let previous = analytics.daily(in: snapshot.previousRange)
            let shift = snapshot.range.length

            let activeUsersCount = max(1, engagement.activeUsers.current)
            let sessionsPerUser = Double(engagement.sessions.current) / Double(activeUsersCount)
            let newUserRatio = Double(engagement.newUsers.current) / Double(activeUsersCount)

            DashboardPage {
                HStack(alignment: .center) {
                    Label("User Engagement & Retention Report", systemImage: "person.2.wave.2.fill")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    #if os(macOS)
                    Button {
                        let filename = "AppBinnacle-Engagement-\(snapshot.app.displayName)-\(snapshot.range.shortLabel).csv"
                        SaveFileDialog.save(filename: filename, content: ReportExporter.exportEngagementCSV(snapshot: snapshot))
                    } label: {
                        Label("Export Engagement CSV", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Export daily engagement metrics to CSV")
                    #endif
                }

                MetricGrid {
                    MetricTile(
                        title: "Active Users",
                        value: Int(engagement.activeUsers.current).formatted(),
                        change: engagement.activeUsers,
                        systemImage: "person.2.fill",
                        accentColor: .indigo
                    )
                    MetricTile(
                        title: "New Users",
                        value: Int(engagement.newUsers.current).formatted(),
                        change: engagement.newUsers,
                        caption: "\(String(format: "%.1f%%", newUserRatio * 100)) of active users",
                        systemImage: "person.badge.plus.fill",
                        accentColor: .blue
                    )
                    MetricTile(
                        title: "Total Sessions",
                        value: Int(engagement.sessions.current).formatted(),
                        change: engagement.sessions,
                        systemImage: "bolt.horizontal.fill",
                        accentColor: .teal
                    )
                    MetricTile(
                        title: "User Stickiness",
                        value: "\(String(format: "%.1f", sessionsPerUser))x",
                        caption: "Sessions per active user",
                        systemImage: "repeat.circle.fill",
                        accentColor: .purple
                    )
                }

                ChartCard(
                    title: "Engagement Dynamics",
                    subtitle: "Solid line: current · Dashed line: previous \(shift) days",
                    systemImage: "person.2.fill",
                    accentColor: .indigo
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("View Mode", selection: $chartMode) {
                                ForEach(EngagementChartMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                            .labelsHidden()

                            Spacer()
                        }

                        switch chartMode {
                        case .activeUsers:
                            Chart {
                                ForEach(current, id: \.day) { day in
                                    LineMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Active users", day.activeUsers))
                                        .foregroundStyle(by: .value("Period", "This period"))
                                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                        .interpolationMethod(.catmullRom)

                                    AreaMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Active users", day.activeUsers))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [Color.indigo.opacity(0.32), Color.indigo.opacity(0.02)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .interpolationMethod(.catmullRom)
                                }
                                ForEach(previous, id: \.day) { day in
                                    LineMark(x: .value("Day", day.day.adding(days: shift).startDate(), unit: .day), y: .value("Active users", day.activeUsers))
                                        .foregroundStyle(by: .value("Period", "Previous period"))
                                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
                                        .interpolationMethod(.catmullRom)
                                }
                            }
                            .chartForegroundStyleScale([
                                "This period": Color.indigo,
                                "Previous period": Color.secondary.opacity(0.7)
                            ])
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
                            .frame(height: 220)

                        case .sessions:
                            Chart {
                                ForEach(current, id: \.day) { day in
                                    BarMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Sessions", day.sessions))
                                        .foregroundStyle(LinearGradient(colors: [.teal, .mint], startPoint: .top, endPoint: .bottom))
                                        .cornerRadius(3)
                                }
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
                            .frame(height: 220)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    ChartCard(
                        title: "New User Acquisition",
                        subtitle: "Daily first-time app opens in GA4",
                        systemImage: "person.badge.plus.fill",
                        accentColor: .blue
                    ) {
                        Chart(current, id: \.day) { day in
                            BarMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("New users", day.newUsers))
                                .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom))
                                .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: max(1, snapshot.range.length / 5))) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .frame(height: 180)
                    }

                    ChartCard(
                        title: "Daily Usage Frequency",
                        subtitle: "Sessions per active user trend",
                        systemImage: "chart.line.uptrend.xyaxis",
                        accentColor: .purple
                    ) {
                        Chart(current, id: \.day) { day in
                            let ratio = day.activeUsers > 0 ? (Double(day.sessions) / Double(day.activeUsers)) : 0
                            LineMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Sessions/User", ratio))
                                .foregroundStyle(Color.purple)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Sessions/User", ratio))
                                .foregroundStyle(Color.purple)
                                .symbolSize(18)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: max(1, snapshot.range.length / 5))) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .frame(height: 180)
                    }
                }
            }
        } else {
            SourceUnavailableView(status: snapshot.status(of: .googleAnalytics), source: .googleAnalytics)
        }
    }
}
