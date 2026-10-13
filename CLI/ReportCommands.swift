import ArgumentParser
import Foundation

struct BriefCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "brief",
        abstract: "Print a compact comparison of the latest period, ready to hand to an AI agent.")

    @OptionGroup var report: ReportOptions

    @Option(name: .shortAndLong, help: "Output format: markdown or json.")
    var format: BriefFormat = .markdown

    mutating func run() async throws {
        let context = try CLIContext.load()
        let apps = try context.apps(matching: report.app)
        let service = SnapshotService(
            configuration: context.configuration, credentials: context.credentials(), useSalesCache: !report.noCache)
        let snapshots = await service.snapshots(for: apps, days: report.days, end: report.end)
        print(try BriefRenderer.render(snapshots.map { BriefBuilder.make(from: $0) }, format: format))
        try exitIfNothingLoaded(snapshots)
    }
}

struct SnapshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Print every daily value behind the dashboards as JSON.")

    @OptionGroup var report: ReportOptions

    mutating func run() async throws {
        let context = try CLIContext.load()
        let apps = try context.apps(matching: report.app)
        let service = SnapshotService(
            configuration: context.configuration, credentials: context.credentials(), useSalesCache: !report.noCache)
        let snapshots = await service.snapshots(for: apps, days: report.days, end: report.end)
        print(snapshots.count == 1 ? try JSONCoding.string(snapshots[0]) : try JSONCoding.string(snapshots))
        try exitIfNothingLoaded(snapshots)
    }
}

/// Exits with status 1 when no data source answered for any app, so scripts can detect broken setups.
private func exitIfNothingLoaded(_ snapshots: [DashboardSnapshot]) throws {
    let anyLoaded = snapshots.contains { snapshot in snapshot.sources.contains { $0.state == .ok } }
    if !anyLoaded {
        Console.error("No data source could be loaded. Run 'binnacle doctor' to check your setup.")
        throw ExitCode.failure
    }
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check credentials and every configured connection.")

    mutating func run() async throws {
        let context = try CLIContext.load()
        let results = await Diagnostics.run(
            configuration: context.configuration,
            credentials: context.credentials(reportProblems: false),
            configurationPath: context.configurationPath)
        for result in results {
            let symbol: String
            switch result.status {
            case .passed: symbol = "✓"
            case .warning: symbol = "!"
            case .failed: symbol = "✗"
            }
            print("\(symbol) \(result.title): \(result.detail)")
        }
        if results.contains(where: { $0.status == .failed }) { throw ExitCode.failure }
    }
}

struct AppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "List tracked apps, or import them from App Store Connect.")

    @Flag(help: "List the apps your App Store Connect key can see instead of the tracked ones.")
    var remote = false

    @Flag(name: .customLong("import"), help: "Track every app your App Store Connect key can see.")
    var importApps = false

    @Flag(help: "Print JSON.")
    var json = false

    mutating func run() async throws {
        var context = try CLIContext.load()
        if remote || importApps {
            guard let asc = context.credentials().appStoreConnect else {
                throw ValidationError("App Store Connect is not configured. Run 'binnacle config set-asc' first.")
            }
            let remoteApps = try await AppStoreConnectClient(credentials: asc).apps()
            if importApps {
                let added = context.configuration.mergeApps(remoteApps)
                try context.save()
                if !json { print("Tracking \(context.configuration.apps.count) apps (\(added) new).") }
            }
            if remote && !importApps {
                if json {
                    print(try JSONCoding.string(remoteApps))
                } else {
                    for app in remoteApps { print("\(app.id)\t\(app.bundleID)\t\(app.name)") }
                }
                return
            }
        }
        let apps = context.configuration.apps
        if json {
            print(try JSONCoding.string(apps))
        } else if apps.isEmpty {
            print("No apps are tracked yet. Run 'binnacle apps --import' to track every app in App Store Connect.")
        } else {
            for app in apps { print(Self.describe(app)) }
        }
    }

    static func describe(_ app: TrackedApp) -> String {
        var parts = ["\(app.displayName) — Apple ID \(app.appleID)"]
        if !app.bundleID.isEmpty { parts.append(app.bundleID) }
        if !app.sku.isEmpty { parts.append("SKU \(app.sku)") }
        parts.append(app.ga4PropertyID.isEmpty ? "GA4 not set" : "GA4 \(app.ga4PropertyID)")
        parts.append(app.firebaseAppID.isEmpty ? "Firebase not set" : "Firebase \(app.firebaseAppID)")
        return parts.joined(separator: " · ")
    }
}
