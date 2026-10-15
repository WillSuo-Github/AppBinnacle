import Charts
import SwiftUI

struct EngagementView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief

    var body: some View {
        if let analytics = snapshot.analytics, let engagement = brief.engagement {
            let current = analytics.daily(in: snapshot.range)
            let previous = analytics.daily(in: snapshot.previousRange)
            let shift = snapshot.range.length

            DashboardPage {
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
                        systemImage: "person.badge.plus.fill",
                        accentColor: .blue
                    )
                    MetricTile(
                        title: "Sessions",
                        value: Int(engagement.sessions.current).formatted(),
                        change: engagement.sessions,
                        systemImage: "bolt.horizontal.fill",
                        accentColor: .teal
                    )
                    MetricTile(
                        title: "Daily Average",
                        value: Int(engagement.averageDailyActiveUsers.rounded()).formatted(),
                        caption: "Active users per day",
                        systemImage: "chart.line.uptrend.xyaxis",
                        accentColor: .purple
                    )
                }

                ChartCard(
                    title: "Daily Active Users",
                    subtitle: "Solid line: current · Dashed line: previous \(shift) days",
                    systemImage: "person.2.fill",
                    accentColor: .indigo
                ) {
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
                    .frame(height: 240)
                }

                HStack(alignment: .top, spacing: 14) {
                    ChartCard(
                        title: "New Users",
                        subtitle: snapshot.range.shortLabel,
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
                        title: "Sessions",
                        subtitle: snapshot.range.shortLabel,
                        systemImage: "bolt.horizontal.fill",
                        accentColor: .teal
                    ) {
                        Chart(current, id: \.day) { day in
                            BarMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Sessions", day.sessions))
                                .foregroundStyle(LinearGradient(colors: [.teal, .mint], startPoint: .top, endPoint: .bottom))
                                .cornerRadius(3)
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
