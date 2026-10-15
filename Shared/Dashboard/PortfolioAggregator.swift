import Foundation

/// Combines snapshots from multiple apps into a single portfolio snapshot representing the developer's entire studio.
enum PortfolioAggregator {
    static func aggregate(
        snapshots: [DashboardSnapshot],
        range: DayRange,
        apps: [TrackedApp]
    ) -> DashboardSnapshot {
        let title = "All Apps (\(apps.count))"
        let portfolioApp = TrackedApp(
            appleID: "all",
            name: title,
            bundleID: "portfolio"
        )

        let generatedAt = snapshots.map(\.generatedAt).max() ?? Date()
        var portfolio = DashboardSnapshot(
            app: portfolioApp,
            generatedAt: generatedAt,
            range: range,
            sources: []
        )

        // 1. Merge Sales Series
        let salesList = snapshots.compactMap(\.sales)
        if !salesList.isEmpty {
            let allDays = Array(Set(salesList.flatMap { $0.days.map(\.day) })).sorted { $0 < $1 }
            let mergedSalesDays: [SalesDay] = allDays.map { day in
                var merged = SalesDay(day: day)
                for s in salesList {
                    if let match = s.days.first(where: { $0.day == day }) {
                        merged.firstDownloads += match.firstDownloads
                        merged.redownloads += match.redownloads
                        merged.updates += match.updates
                        merged.inAppPurchases += match.inAppPurchases
                        for (curr, amt) in match.proceeds {
                            merged.proceeds[curr, default: 0] += amt
                        }
                        for (country, units) in match.firstDownloadsByCountry {
                            merged.firstDownloadsByCountry[country, default: 0] += units
                        }
                        for (type, units) in match.otherProductTypes {
                            merged.otherProductTypes[type, default: 0] += units
                        }
                    }
                }
                return merged
            }
            let throughDay = salesList.map(\.throughDay).max() ?? range.end
            let pendingDays = Array(Set(salesList.flatMap(\.pendingDays))).sorted { $0 < $1 }
            portfolio.sales = SalesSeries(days: mergedSalesDays, throughDay: throughDay, pendingDays: pendingDays)
        }

        // 2. Merge Google Analytics Reports
        let analyticsList = snapshots.compactMap(\.analytics)
        if !analyticsList.isEmpty {
            let allDays = Array(Set(analyticsList.flatMap { $0.daily.map(\.day) })).sorted { $0 < $1 }
            let mergedDaily: [AnalyticsDay] = allDays.map { day in
                var merged = AnalyticsDay(day: day)
                var rates: [Double] = []
                for a in analyticsList {
                    if let match = a.daily.first(where: { $0.day == day }) {
                        merged.activeUsers += match.activeUsers
                        merged.newUsers += match.newUsers
                        merged.sessions += match.sessions
                        if let rate = match.crashFreeUsersRate {
                            rates.append(rate)
                        }
                    }
                }
                if !rates.isEmpty {
                    merged.crashFreeUsersRate = rates.reduce(0, +) / Double(rates.count)
                }
                return merged
            }

            let currentActive = analyticsList.reduce(0) { $0 + $1.current.activeUsers }
            let currentNew = analyticsList.reduce(0) { $0 + $1.current.newUsers }
            let currentSessions = analyticsList.reduce(0) { $0 + $1.current.sessions }
            let currentRates = analyticsList.compactMap { $0.current.crashFreeUsersRate }
            let currentRate = currentRates.isEmpty ? nil : (currentRates.reduce(0, +) / Double(currentRates.count))

            let prevActive = analyticsList.reduce(0) { $0 + $1.previous.activeUsers }
            let prevNew = analyticsList.reduce(0) { $0 + $1.previous.newUsers }
            let prevSessions = analyticsList.reduce(0) { $0 + $1.previous.sessions }
            let prevRates = analyticsList.compactMap { $0.previous.crashFreeUsersRate }
            let prevRate = prevRates.isEmpty ? nil : (prevRates.reduce(0, +) / Double(prevRates.count))

            let allVersions = analyticsList.flatMap(\.versions).sorted { $0.activeUsers > $1.activeUsers }

            portfolio.analytics = AnalyticsReport(
                daily: mergedDaily,
                current: AnalyticsTotals(activeUsers: currentActive, newUsers: currentNew, sessions: currentSessions, crashFreeUsersRate: currentRate),
                previous: AnalyticsTotals(activeUsers: prevActive, newUsers: prevNew, sessions: prevSessions, crashFreeUsersRate: prevRate),
                versions: Array(allVersions.prefix(10))
            )
        }

        // 3. Merge Crashlytics Issues
        let issues = snapshots.compactMap(\.crashIssues).flatMap { $0 }
        if !issues.isEmpty {
            portfolio.crashIssues = issues
        }

        // 4. Merge Reviews
        let reviews = snapshots.compactMap(\.reviews).flatMap { $0 }.sorted { $0.day > $1.day }
        if !reviews.isEmpty {
            portfolio.reviews = reviews
        }

        // 5. Merge Data Sources Status
        for source in DataSource.allCases {
            let statuses = snapshots.compactMap { $0.status(of: source) }
            let maxSync = statuses.compactMap(\.lastSyncedAt).max() ?? generatedAt
            if statuses.contains(where: { $0.state == .ok }) {
                portfolio.sources.append(SourceStatus(source: source, state: .ok, lastSyncedAt: maxSync))
            } else if statuses.contains(where: { $0.state == .failed }) {
                let detail = statuses.first { $0.state == .failed }?.detail
                portfolio.sources.append(SourceStatus(source: source, state: .failed, detail: detail))
            } else {
                portfolio.sources.append(SourceStatus(source: source, state: .notConfigured, detail: "Not configured"))
            }
        }

        return portfolio
    }
}
