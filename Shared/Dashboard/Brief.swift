import Foundation

struct MetricChange: Codable, Equatable, Sendable {
    var current: Double
    var previous: Double
    /// Nil when the previous value is zero.
    var changePercent: Double?

    init(current: Double, previous: Double) {
        self.current = current
        self.previous = previous
        changePercent = previous == 0 ? nil : (current - previous) / previous * 100
    }

    init(_ current: Int, _ previous: Int) {
        self.init(current: Double(current), previous: Double(previous))
    }
}

/// A compact, comparison-first summary of one app, designed to be pasted into an AI conversation.
struct AppBrief: Codable, Equatable, Sendable {
    struct AppInfo: Codable, Equatable, Sendable {
        var name: String
        var bundleID: String
        var appleID: String
    }

    struct Acquisition: Codable, Equatable, Sendable {
        var period: DayRange
        var comparison: DayRange
        var firstDownloads: MetricChange
        var redownloads: MetricChange
        var updates: Int
        var inAppPurchases: MetricChange
        var proceeds: [CurrencyProceeds]
        var topCountries: [CountryDownloads]
        var unclassifiedProductTypes: [String: Int]
    }

    struct CurrencyProceeds: Codable, Equatable, Sendable {
        var currency: String
        var current: Decimal
        var previous: Decimal
    }

    struct CountryDownloads: Codable, Equatable, Sendable {
        var country: String
        var firstDownloads: Int
    }

    struct Engagement: Codable, Equatable, Sendable {
        var activeUsers: MetricChange
        var newUsers: MetricChange
        var sessions: MetricChange
        var averageDailyActiveUsers: Double
    }

    struct Stability: Codable, Equatable, Sendable {
        var crashFreeUsersRate: Double?
        var previousCrashFreeUsersRate: Double?
        var crashAffectedUsers: MetricChange?
        var weakestVersions: [VersionStability]
        var openIssues: [CrashIssue]?
    }

    struct Reviews: Codable, Equatable, Sendable {
        var count: Int
        var previousCount: Int
        var averageRating: Double?
        var lowRatingCount: Int
        var recentLowRatings: [ReviewExcerpt]
    }

    struct ReviewExcerpt: Codable, Equatable, Sendable {
        var rating: Int
        var title: String
        var excerpt: String
        var territory: String
        var day: Day
    }

    var app: AppInfo
    var generatedAt: Date
    var period: DayRange
    var comparison: DayRange
    var acquisition: Acquisition?
    var engagement: Engagement?
    var stability: Stability?
    var reviews: Reviews?
    var highlights: [String]
    var sources: [SourceStatus]
}

enum BriefBuilder {
    /// Proceeds list the preferred currency first, then USD, then the rest by amount.
    /// Amounts in different currencies are never compared with each other.
    static func make(from snapshot: DashboardSnapshot,
                     preferredCurrency: String? = Locale.current.currency?.identifier) -> AppBrief {
        var brief = AppBrief(
            app: .init(name: snapshot.app.displayName, bundleID: snapshot.app.bundleID, appleID: snapshot.app.appleID),
            generatedAt: snapshot.generatedAt,
            period: snapshot.range,
            comparison: snapshot.previousRange,
            highlights: [],
            sources: snapshot.sources)
        brief.acquisition = acquisition(snapshot, preferredCurrency: preferredCurrency)
        brief.engagement = engagement(snapshot)
        brief.stability = stability(snapshot)
        brief.reviews = reviews(snapshot)
        brief.highlights = highlights(for: brief)
        return brief
    }

    static func acquisition(_ snapshot: DashboardSnapshot, preferredCurrency: String?) -> AppBrief.Acquisition? {
        guard let sales = snapshot.sales, let range = snapshot.salesRange else { return nil }
        let previous = range.previous
        let currentProceeds = sales.proceeds(in: range)
        let previousProceeds = sales.proceeds(in: previous)
        let currencies = Set(currentProceeds.keys).union(previousProceeds.keys)
        let proceeds = currencies
            .map { AppBrief.CurrencyProceeds(currency: $0, current: currentProceeds[$0] ?? 0, previous: previousProceeds[$0] ?? 0) }
            .sorted { lhs, rhs in
                let left = currencyRank(lhs.currency, preferred: preferredCurrency)
                let right = currencyRank(rhs.currency, preferred: preferredCurrency)
                if left != right { return left < right }
                if lhs.current != rhs.current { return lhs.current > rhs.current }
                return lhs.currency < rhs.currency
            }
        let countries = sales.firstDownloadsByCountry(in: range)
            .filter { $0.value > 0 }
            .map { AppBrief.CountryDownloads(country: $0.key, firstDownloads: $0.value) }
            .sorted { ($0.firstDownloads, $1.country) > ($1.firstDownloads, $0.country) }
        return AppBrief.Acquisition(
            period: range,
            comparison: previous,
            firstDownloads: MetricChange(sales.total(\.firstDownloads, in: range), sales.total(\.firstDownloads, in: previous)),
            redownloads: MetricChange(sales.total(\.redownloads, in: range), sales.total(\.redownloads, in: previous)),
            updates: sales.total(\.updates, in: range),
            inAppPurchases: MetricChange(sales.total(\.inAppPurchases, in: range), sales.total(\.inAppPurchases, in: previous)),
            proceeds: proceeds,
            topCountries: Array(countries.prefix(5)),
            unclassifiedProductTypes: sales.otherProductTypes(in: range))
    }

    private static func currencyRank(_ currency: String, preferred: String?) -> Int {
        if currency == preferred { return 0 }
        return currency == "USD" ? 1 : 2
    }

    static func engagement(_ snapshot: DashboardSnapshot) -> AppBrief.Engagement? {
        guard let analytics = snapshot.analytics else { return nil }
        let days = analytics.daily(in: snapshot.range)
        let average = days.isEmpty ? 0 : Double(days.reduce(0) { $0 + $1.activeUsers }) / Double(days.count)
        return AppBrief.Engagement(
            activeUsers: MetricChange(analytics.current.activeUsers, analytics.previous.activeUsers),
            newUsers: MetricChange(analytics.current.newUsers, analytics.previous.newUsers),
            sessions: MetricChange(analytics.current.sessions, analytics.previous.sessions),
            averageDailyActiveUsers: average)
    }

    static func stability(_ snapshot: DashboardSnapshot) -> AppBrief.Stability? {
        guard snapshot.analytics != nil || snapshot.crashIssues != nil else { return nil }
        var stability = AppBrief.Stability(weakestVersions: [], openIssues: snapshot.crashIssues)
        if let analytics = snapshot.analytics {
            stability.crashFreeUsersRate = analytics.current.crashFreeUsersRate
            stability.previousCrashFreeUsersRate = analytics.previous.crashFreeUsersRate
            stability.crashAffectedUsers = MetricChange(analytics.current.crashAffectedUsers, analytics.previous.crashAffectedUsers)
            stability.weakestVersions = weakestVersions(analytics)
        }
        return stability
    }

    /// Versions with a meaningful audience and at least one crash, lowest crash-free rate first.
    static func weakestVersions(_ analytics: AnalyticsReport, limit: Int = 3) -> [VersionStability] {
        let minimumUsers = max(20, Int(Double(analytics.current.activeUsers) * 0.02))
        return analytics.versions
            .filter { $0.activeUsers >= minimumUsers && $0.crashAffectedUsers > 0 && $0.crashFreeUsersRate != nil }
            .sorted { ($0.crashFreeUsersRate ?? 1) < ($1.crashFreeUsersRate ?? 1) }
            .prefix(limit)
            .map { $0 }
    }

    static func reviews(_ snapshot: DashboardSnapshot) -> AppBrief.Reviews? {
        guard let reviews = snapshot.reviews else { return nil }
        let current = reviews.filter { snapshot.range.contains($0.day) }
        let previousCount = reviews.filter { snapshot.previousRange.contains($0.day) }.count
        let low = current.filter { $0.rating <= 2 }.sorted { $0.createdDate > $1.createdDate }
        return AppBrief.Reviews(
            count: current.count,
            previousCount: previousCount,
            averageRating: current.isEmpty ? nil : Double(current.reduce(0) { $0 + $1.rating }) / Double(current.count),
            lowRatingCount: low.count,
            recentLowRatings: low.prefix(3).map {
                AppBrief.ReviewExcerpt(rating: $0.rating, title: $0.title, excerpt: excerpt($0.body), territory: $0.territory, day: $0.day)
            })
    }

    static func highlights(for brief: AppBrief) -> [String] {
        var notes: [String] = []
        if let acquisition = brief.acquisition {
            if let note = changeNote("First downloads", acquisition.firstDownloads, threshold: 20, minimumBase: 20) { notes.append(note) }
            if let note = changeNote("In-app purchases", acquisition.inAppPurchases, threshold: 25, minimumBase: 10) { notes.append(note) }
        }
        if let engagement = brief.engagement {
            if let note = changeNote("Active users", engagement.activeUsers, threshold: 15, minimumBase: 50) { notes.append(note) }
        }
        if let stability = brief.stability {
            if let rate = stability.crashFreeUsersRate {
                if let previous = stability.previousCrashFreeUsersRate, previous - rate >= 0.003 {
                    notes.append("Crash-free users fell \(Format.points(previous - rate)) to \(Format.rate(rate)).")
                } else if rate < 0.99 {
                    notes.append("Crash-free users are at \(Format.rate(rate)), below the 99% mark.")
                }
            }
            if let version = stability.weakestVersions.first, let rate = version.crashFreeUsersRate, rate < 0.99 {
                notes.append("Version \(version.version) has \(Format.rate(rate)) crash-free users (\(Format.integer(version.activeUsers)) active users).")
            }
            if let issue = stability.openIssues?.first(where: { $0.errorType == "FATAL" }) ?? stability.openIssues?.first {
                notes.append("Top open Crashlytics issue: \(issue.title) (\(Format.integer(issue.events)) events, \(Format.integer(issue.impactedUsers)) users).")
            }
        }
        if let reviews = brief.reviews {
            if reviews.lowRatingCount > 0 {
                notes.append("\(reviews.lowRatingCount) new 1–2★ review\(reviews.lowRatingCount == 1 ? "" : "s").")
            }
            if let average = reviews.averageRating, reviews.count >= 5, average < 4 {
                notes.append("Average rating of new reviews is \(Format.number(average))★.")
            }
        }
        let failed = brief.sources.filter { $0.state == .failed }.map(\.source.title)
        if !failed.isEmpty {
            notes.append("Could not load: \(failed.joined(separator: ", ")). See Data sources.")
        } else if !brief.sources.isEmpty, brief.sources.allSatisfy({ $0.state == .notConfigured }) {
            notes.append("No data sources are connected yet. See Data sources.")
        }
        return notes
    }

    private static func changeNote(_ name: String, _ change: MetricChange, threshold: Double, minimumBase: Double) -> String? {
        guard change.previous >= minimumBase, let percent = change.changePercent, abs(percent) >= threshold else { return nil }
        let direction = percent < 0 ? "fell" : "rose"
        return "\(name) \(direction) \(Format.percent(abs(percent))) (\(Format.integer(change.previous)) → \(Format.integer(change.current)))."
    }

    private static func excerpt(_ text: String, limit: Int = 220) -> String {
        let flattened = text.split(whereSeparator: \.isNewline).map { $0.trimmed }.filter { !$0.isEmpty }.joined(separator: " ")
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)).trimmed + "…"
    }
}

enum BriefFormat: String, CaseIterable, Sendable {
    case markdown
    case json
    case csv
}

enum BriefRenderer {
    static func render(_ briefs: [AppBrief], format: BriefFormat) throws -> String {
        switch format {
        case .markdown:
            return briefs.map(markdown).joined(separator: "\n\n---\n\n")
        case .json:
            return briefs.count == 1 ? try JSONCoding.string(briefs[0]) : try JSONCoding.string(briefs)
        case .csv:
            return csv(briefs)
        }
    }

    static func csv(_ briefs: [AppBrief]) -> String {
        var rows: [[String]] = []
        rows.append([
            "App Name", "Apple ID", "Bundle ID", "Period Start", "Period End", "Generated At",
            "First Downloads", "Prev Downloads", "Download Change %",
            "Redownloads", "Updates", "In-App Purchases", "Proceeds",
            "Active Users", "Prev Active Users", "Active Users Change %",
            "New Users", "Sessions", "Avg Daily Active Users",
            "Crash-Free Users %", "Prev Crash-Free %", "Open Issues",
            "New Reviews", "Avg Rating"
        ])

        for brief in briefs {
            let acq = brief.acquisition
            let eng = brief.engagement
            let stab = brief.stability
            let rev = brief.reviews

            let proceedsString = acq?.proceeds.map { "\($0.current) \($0.currency)" }.joined(separator: "; ") ?? ""

            rows.append([
                brief.app.name,
                brief.app.appleID,
                brief.app.bundleID,
                brief.period.start.iso,
                brief.period.end.iso,
                brief.generatedAt.ISO8601Format(),
                acq.map { "\($0.firstDownloads.current)" } ?? "",
                acq.map { "\($0.firstDownloads.previous)" } ?? "",
                acq?.firstDownloads.changePercent.map { String(format: "%.1f", $0) } ?? "",
                acq.map { "\($0.redownloads.current)" } ?? "",
                acq.map { "\($0.updates)" } ?? "",
                acq.map { "\($0.inAppPurchases.current)" } ?? "",
                proceedsString,
                eng.map { "\($0.activeUsers.current)" } ?? "",
                eng.map { "\($0.activeUsers.previous)" } ?? "",
                eng?.activeUsers.changePercent.map { String(format: "%.1f", $0) } ?? "",
                eng.map { "\($0.newUsers.current)" } ?? "",
                eng.map { "\($0.sessions.current)" } ?? "",
                eng.map { String(format: "%.1f", $0.averageDailyActiveUsers) } ?? "",
                stab?.crashFreeUsersRate.map { String(format: "%.2f%%", $0 * 100) } ?? "",
                stab?.previousCrashFreeUsersRate.map { String(format: "%.2f%%", $0 * 100) } ?? "",
                stab?.openIssues.map { "\($0.count)" } ?? "",
                rev.map { "\($0.count)" } ?? "",
                rev?.averageRating.map { String(format: "%.2f", $0) } ?? ""
            ])
        }

        return ReportExporter.formatCSV(rows)
    }

    static func markdown(_ brief: AppBrief) -> String {
        var lines: [String] = []
        lines.append("# \(brief.app.name) — \(brief.period.start.iso) to \(brief.period.end.iso)")
        var identity = ["Apple ID \(brief.app.appleID)"]
        if !brief.app.bundleID.isEmpty { identity.insert(brief.app.bundleID, at: 0) }
        lines.append("\(identity.joined(separator: " · ")) · compared with \(brief.comparison.start.iso) to \(brief.comparison.end.iso) · generated \(brief.generatedAt.ISO8601Format())")

        lines.append("")
        lines.append("## Highlights")
        if brief.highlights.isEmpty {
            lines.append("- No notable changes.")
        } else {
            lines += brief.highlights.map { "- \($0)" }
        }

        if let acquisition = brief.acquisition {
            lines.append("")
            lines.append("## Acquisition (App Store)")
            if acquisition.period != brief.period {
                lines.append("Reports are published through \(acquisition.period.end.iso), so this compares \(acquisition.period) with \(acquisition.comparison).")
            }
            lines.append(contentsOf: table([
                ("First downloads", acquisition.firstDownloads),
                ("Redownloads", acquisition.redownloads),
                ("In-app purchases", acquisition.inAppPurchases),
            ]))
            lines.append("Updates: \(Format.integer(acquisition.updates))")
            if !acquisition.proceeds.isEmpty {
                let proceeds = acquisition.proceeds.map {
                    "\(Format.money($0.current, currency: $0.currency)) (previous \(Format.money($0.previous, currency: $0.currency)))"
                }
                lines.append("Proceeds: \(proceeds.joined(separator: "; "))")
            }
            if !acquisition.topCountries.isEmpty {
                lines.append("Top countries by first downloads: " + acquisition.topCountries.map { "\($0.country) \(Format.integer($0.firstDownloads))" }.joined(separator: ", "))
            }
            if !acquisition.unclassifiedProductTypes.isEmpty {
                let types = acquisition.unclassifiedProductTypes.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }
                lines.append("Not counted above (unclassified product types): \(types.joined(separator: ", "))")
            }
        }

        if let engagement = brief.engagement {
            lines.append("")
            lines.append("## Engagement (Google Analytics)")
            lines.append(contentsOf: table([
                ("Active users", engagement.activeUsers),
                ("New users", engagement.newUsers),
                ("Sessions", engagement.sessions),
            ]))
            lines.append("Average daily active users: \(Format.integer(engagement.averageDailyActiveUsers))")
        }

        if let stability = brief.stability {
            lines.append("")
            lines.append("## Stability")
            if stability.crashFreeUsersRate != nil || stability.crashAffectedUsers != nil {
                var line = "Crash-free users: \(Format.rate(stability.crashFreeUsersRate))"
                if let previous = stability.previousCrashFreeUsersRate {
                    line += " (previous \(Format.rate(previous)))"
                }
                if let affected = stability.crashAffectedUsers {
                    line += "; crash-affected users \(Format.integer(affected.current)) (previous \(Format.integer(affected.previous)))"
                }
                lines.append(line)
            }
            if !stability.weakestVersions.isEmpty {
                lines.append("Weakest versions: " + stability.weakestVersions.map {
                    "\($0.version) \(Format.rate($0.crashFreeUsersRate)) of \(Format.integer($0.activeUsers)) users"
                }.joined(separator: "; "))
            }
            if let issues = stability.openIssues {
                if issues.isEmpty {
                    lines.append("Open Crashlytics issues: none in this period.")
                } else {
                    lines.append("Open Crashlytics issues:")
                    for (index, issue) in issues.prefix(5).enumerated() {
                        let kind = issue.errorType.isEmpty ? "" : "[\(issue.errorType)] "
                        let detail = issue.subtitle.isEmpty ? "" : " — \(issue.subtitle)"
                        lines.append("\(index + 1). \(kind)\(issue.title)\(detail) · \(Format.integer(issue.events)) events · \(Format.integer(issue.impactedUsers)) users")
                    }
                }
            }
        }

        if let reviews = brief.reviews {
            lines.append("")
            lines.append("## Reviews")
            var line = "\(reviews.count) new review\(reviews.count == 1 ? "" : "s") (previous \(reviews.previousCount))"
            if let average = reviews.averageRating { line += ", average \(Format.number(average))★" }
            line += ", \(reviews.lowRatingCount) rated 1–2★"
            lines.append(line)
            for review in reviews.recentLowRatings {
                let title = review.title.isEmpty ? "" : "\"\(review.title)\" "
                lines.append("- \(review.rating)★ \(title)(\(review.territory), \(review.day.iso)): \(review.excerpt)")
            }
        }

        lines.append("")
        lines.append("## Data sources")
        for status in brief.sources {
            var line = "- \(status.source.title): \(label(status.state))"
            if let detail = status.detail, !detail.isEmpty { line += " — \(detail)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func label(_ state: SourceStatus.State) -> String {
        switch state {
        case .ok: return "ok"
        case .notConfigured: return "not configured"
        case .failed: return "failed"
        }
    }

    private static func table(_ rows: [(String, MetricChange)]) -> [String] {
        ["| Metric | Current | Previous | Change |", "|---|---:|---:|---:|"] + rows.map { name, change in
            "| \(name) | \(Format.integer(change.current)) | \(Format.integer(change.previous)) | \(Format.signedPercent(change.changePercent)) |"
        }
    }
}
