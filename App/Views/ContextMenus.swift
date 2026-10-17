import AppKit
import SwiftUI

enum Clipboard {
    @MainActor static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct CopyMenuItem: View {
    let title: String
    let text: String

    var body: some View {
        Button { Clipboard.copy(text) } label: {
            Label(title, systemImage: "doc.on.doc")
        }
        .disabled(text.isEmpty)
    }
}

struct RefreshMenuItems: View {
    @Environment(DashboardModel.self) private var model

    var body: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            Label("Refresh Data", systemImage: "arrow.clockwise")
        }
        .disabled(model.configuration.apps.isEmpty || model.isRefreshing)
        SettingsLink { Label("Settings…", systemImage: "gearshape") }
    }
}

/// The displayed snapshot owns menu exports, including inside a pushed app dashboard.
struct DashboardReportContext: Equatable, Sendable {
    let snapshot: DashboardSnapshot
    let section: DashboardSection
}

private struct DashboardReportContextKey: SwiftUI.EnvironmentKey {
    static let defaultValue: DashboardReportContext? = nil
}

extension EnvironmentValues {
    var dashboardReportContext: DashboardReportContext? {
        get { self[DashboardReportContextKey.self] }
        set { self[DashboardReportContextKey.self] = newValue }
    }
}

struct ReportMenuItems: View {
    let context: DashboardReportContext
    @Environment(DashboardModel.self) private var model

    var body: some View {
        if context.section != .brief {
            Button {
                model.push(.section(.brief, appID: appID))
            } label: {
                Label("Open AI Brief", systemImage: "text.quote")
            }
        }
        Button {
            if let text = try? BriefRenderer.render(briefs, format: .markdown) {
                Clipboard.copy(text)
            }
        } label: {
            Label("Copy Brief as Markdown", systemImage: "doc.on.doc")
        }
        Menu {
            if context.section == .overview || context.section == .brief {
                ForEach([DashboardSection.acquisition, .engagement, .stability, .reviews]) { section in
                    CSVMenuItems(snapshot: context.snapshot, section: section)
                }
            } else {
                CSVMenuItems(snapshot: context.snapshot, section: context.section)
            }
        } label: {
            Label("Export Data", systemImage: "arrow.down.doc")
        }
        Divider()
        RefreshMenuItems()
    }

    private var appID: String? {
        context.snapshot.app.appleID == DashboardModel.allAppsID ? nil : context.snapshot.app.appleID
    }

    private var briefs: [AppBrief] {
        let snapshots = appID == nil && !model.loadedSnapshots.isEmpty
            ? model.loadedSnapshots : [context.snapshot]
        return snapshots.map { model.displayBrief(BriefBuilder.make(from: $0)) }
    }
}

struct CSVMenuItems: View {
    let snapshot: DashboardSnapshot
    let section: DashboardSection

    var body: some View {
        Button("Export \(section.title) CSV…") {
            SaveFileDialog.save(
                filename: "AppBinnacle-\(section.rawValue)-\(snapshot.app.displayName)-\(snapshot.range.shortLabel).csv",
                content: csv
            )
        }
        .disabled(!isAvailable)
        Button("Copy \(section.title) CSV") { Clipboard.copy(csv) }
            .disabled(!isAvailable)
    }

    private var isAvailable: Bool {
        switch section {
        case .acquisition: snapshot.sales != nil && snapshot.salesRange != nil
        case .engagement: snapshot.analytics != nil
        case .stability: snapshot.analytics != nil || snapshot.crashIssues != nil
        case .reviews: snapshot.reviews != nil
        default: false
        }
    }

    private var csv: String {
        switch section {
        case .acquisition: ReportExporter.exportSalesCSV(snapshot: snapshot)
        case .engagement: ReportExporter.exportEngagementCSV(snapshot: snapshot)
        case .stability: ReportExporter.exportStabilityCSV(snapshot: snapshot)
        case .reviews: ReportExporter.exportReviewsCSV(snapshot: snapshot)
        default: ""
        }
    }
}

struct AppMenuItems: View {
    let app: TrackedApp
    var showsDashboardLinks = true
    @Environment(DashboardModel.self) private var model

    var body: some View {
        if showsDashboardLinks {
            Menu {
                ForEach(DashboardSection.allCases) { section in
                    Button {
                        model.navigationPath.removeAll()
                        model.selectedAppID = app.appleID
                        model.selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            } label: {
                Label("Open Dashboard", systemImage: "chart.bar.xaxis")
            }
            Divider()
        }
        if let url = URL(string: "https://apps.apple.com/app/id\(app.appleID)") {
            Link(destination: url) {
                Label("View in App Store", systemImage: "arrow.up.forward.app")
            }
        }
        if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(app.appleID)") {
            Link(destination: url) {
                Label("Open App Store Connect", systemImage: "arrow.up.forward.square")
            }
        }
        Divider()
        CopyMenuItem(title: "Copy App Name", text: app.displayName)
        CopyMenuItem(title: "Copy Apple ID", text: app.appleID)
        CopyMenuItem(title: "Copy Bundle ID", text: app.bundleID)
    }
}

struct SourceMenuItems: View {
    let title: String
    let details: String
    @Environment(DashboardModel.self) private var model

    var body: some View {
        CopyMenuItem(title: "Copy Status Details", text: "\(title)\n\(details)")
        Button {
            Task { await model.runDiagnostics() }
        } label: {
            Label("Check Connections", systemImage: "network")
        }
        .disabled(model.isRunningDiagnostics)
        Divider()
        RefreshMenuItems()
    }
}

struct FileMenuItems: View {
    let url: URL

    var body: some View {
        CopyMenuItem(title: "Copy Path", text: url.path(percentEncoded: false))
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
        .disabled(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
