import Foundation

enum ReportExporter {
    static func exportSalesCSV(snapshot: DashboardSnapshot) -> String {
        guard let sales = snapshot.sales, let range = snapshot.salesRange else { return "" }
        var rows: [[String]] = []
        rows.append(["Date", "App", "Apple ID", "First Downloads", "Redownloads", "Updates", "In-App Purchases", "Proceeds"])
        for day in sales.days(in: range) {
            let proceeds = day.proceeds.map { "\($0.value) \($0.key)" }.joined(separator: "; ")
            rows.append([
                day.day.iso,
                snapshot.app.displayName,
                snapshot.app.appleID,
                "\(day.firstDownloads)",
                "\(day.redownloads)",
                "\(day.updates)",
                "\(day.inAppPurchases)",
                proceeds
            ])
        }
        return formatCSV(rows)
    }

    static func exportEngagementCSV(snapshot: DashboardSnapshot) -> String {
        guard let analytics = snapshot.analytics else { return "" }
        var rows: [[String]] = []
        rows.append(["Date", "App", "Active Users", "New Users", "Sessions", "Crash-Free Rate %"])
        for day in analytics.daily(in: snapshot.range) {
            let rate = day.crashFreeUsersRate.map { String(format: "%.2f%%", $0 * 100) } ?? ""
            rows.append([
                day.day.iso,
                snapshot.app.displayName,
                "\(day.activeUsers)",
                "\(day.newUsers)",
                "\(day.sessions)",
                rate
            ])
        }
        return formatCSV(rows)
    }

    static func exportReviewsCSV(snapshot: DashboardSnapshot) -> String {
        guard let reviews = snapshot.reviews else { return "" }
        var rows: [[String]] = []
        rows.append(["Date", "App", "Rating", "Title", "Reviewer", "Territory", "Body"])
        for review in reviews {
            rows.append([
                review.day.iso,
                snapshot.app.displayName,
                "\(review.rating)",
                review.title,
                review.reviewerNickname,
                review.territory,
                review.body
            ])
        }
        return formatCSV(rows)
    }

    static func exportStabilityCSV(snapshot: DashboardSnapshot) -> String {
        var rows: [[String]] = []
        rows.append(["Type", "App", "Metric / Issue", "Events / Active Users", "Impacted Users / Crash Rate", "Details"])
        if let analytics = snapshot.analytics {
            for v in analytics.versions {
                rows.append([
                    "Version Stability",
                    snapshot.app.displayName,
                    v.version,
                    "\(v.activeUsers) active users",
                    v.crashFreeUsersRate.map { String(format: "%.2f%% crash-free", $0 * 100) } ?? "N/A",
                    "\(v.crashAffectedUsers) affected"
                ])
            }
        }
        if let issues = snapshot.crashIssues {
            for issue in issues {
                rows.append([
                    issue.errorType,
                    snapshot.app.displayName,
                    issue.title,
                    "\(issue.events) events",
                    "\(issue.impactedUsers) users",
                    issue.subtitle
                ])
            }
        }
        return formatCSV(rows)
    }

    static func formatCSV(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                if field.contains(",") || field.contains("\"") || field.contains("\n") {
                    return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return field
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }
}
