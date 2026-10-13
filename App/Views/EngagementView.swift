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
                    MetricTile(title: "Active Users", value: Int(engagement.activeUsers.current).formatted(), change: engagement.activeUsers)
                    MetricTile(title: "New Users", value: Int(engagement.newUsers.current).formatted(), change: engagement.newUsers)
                    MetricTile(title: "Sessions", value: Int(engagement.sessions.current).formatted(), change: engagement.sessions)
                    MetricTile(title: "Daily Average", value: Int(engagement.averageDailyActiveUsers.rounded()).formatted(), caption: "Active users per day")
                }

                ChartCard(title: "Daily Active Users", subtitle: "Dashed line: the previous \(shift) days, shifted to line up") {
                    Chart {
                        ForEach(current, id: \.day) { day in
                            LineMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Active users", day.activeUsers))
                                .foregroundStyle(by: .value("Period", "This period"))
                                .interpolationMethod(.monotone)
                        }
                        ForEach(previous, id: \.day) { day in
                            LineMark(x: .value("Day", day.day.adding(days: shift).startDate(), unit: .day), y: .value("Active users", day.activeUsers))
                                .foregroundStyle(by: .value("Period", "Previous period"))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartForegroundStyleScale(["This period": Color.accentColor, "Previous period": Color.secondary])
                    .frame(height: 240)
                }

                HStack(alignment: .top, spacing: 12) {
                    ChartCard(title: "New Users", subtitle: snapshot.range.shortLabel) {
                        Chart(current, id: \.day) { day in
                            BarMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("New users", day.newUsers))
                        }
                        .frame(height: 180)
                    }
                    ChartCard(title: "Sessions", subtitle: snapshot.range.shortLabel) {
                        Chart(current, id: \.day) { day in
                            BarMark(x: .value("Day", day.day.startDate(), unit: .day), y: .value("Sessions", day.sessions))
                                .foregroundStyle(.teal)
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
