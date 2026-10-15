import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case acquisition
    case engagement
    case stability
    case reviews
    case brief

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .acquisition: return "Downloads & Revenue"
        case .engagement: return "Engagement"
        case .stability: return "Stability"
        case .reviews: return "Reviews"
        case .brief: return "AI Brief"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .acquisition: return "arrow.down.circle"
        case .engagement: return "person.2"
        case .stability: return "bolt.heart"
        case .reviews: return "star.bubble"
        case .brief: return "text.quote"
        }
    }
}

struct ContentView: View {
    @Environment(DashboardModel.self) private var model
    @SceneStorage("dashboardSection") private var storedSection = DashboardSection.overview.rawValue
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        NavigationSplitView {
            List(selection: sectionSelection) {
                Section {
                    ForEach(DashboardSection.allCases) { section in
                        Label {
                            Text(section.title)
                                .font(.system(size: 13, weight: .medium))
                        } icon: {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .tag(section)
                    }
                } header: {
                    Text("Dashboards")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            DetailView(section: DashboardSection(rawValue: storedSection) ?? .overview)
        }
        .tint(Color.accentColor)
        .toolbar { toolbarContent }
        .task(id: model.selectionKey) {
            await model.loadSelection()
        }
        #if DEBUG
        .onAppear(perform: applyDebugLaunchOptions)
        #endif
    }

    #if DEBUG
    /// Debug builds accept "--section <name>" and "--show-settings" so screens can be checked without clicking.
    private func applyDebugLaunchOptions() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--section"), arguments.indices.contains(index + 1),
           let section = DashboardSection(rawValue: arguments[index + 1]) {
            storedSection = section.rawValue
        }
        if arguments.contains("--show-settings") { openSettings() }
    }
    #endif

    private var sectionSelection: Binding<DashboardSection?> {
        Binding(
            get: { DashboardSection(rawValue: storedSection) ?? .overview },
            set: { storedSection = ($0 ?? .overview).rawValue })
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var model = model
        ToolbarItemGroup(placement: .primaryAction) {
            if !model.configuration.apps.isEmpty {
                Menu {
                    Button {
                        model.selectedAppID = DashboardModel.allAppsID
                    } label: {
                        HStack {
                            Label("All Apps (\(model.configuration.apps.count))", systemImage: "square.stack.3d.up.fill")
                            if model.isAllApps {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(model.configuration.apps) { app in
                        Button {
                            model.selectedAppID = app.appleID
                        } label: {
                            HStack {
                                Text(app.displayName)
                                if model.selectedAppID == app.appleID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.isAllApps ? "square.stack.3d.up.fill" : "app.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(model.isAllApps ? "All Apps (\(model.configuration.apps.count))" : (model.selectedApp?.displayName ?? "Select App"))
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderedButton)
                .help("Choose tracked application or view all")

                Picker("Period", selection: $model.rangeDays) {
                    ForEach(DashboardModel.rangeOptions, id: \.self) { days in
                        Text("\(days)D").tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .help("Time window (7, 14, 30, or 90 days)")
            }

            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.configuration.apps.isEmpty || model.isRefreshing)
            .help("Refresh data (⌘R)")
        }
    }
}

private struct DetailView: View {
    let section: DashboardSection
    @Environment(DashboardModel.self) private var model

    var body: some View {
        Group {
            if model.configuration.apps.isEmpty {
                OnboardingView()
            } else if let snapshot = model.snapshot, let brief = model.brief {
                content(snapshot: snapshot, brief: brief)
                    .navigationSubtitle(
                        model.isAllApps
                        ? "Portfolio · \(model.configuration.apps.count) Apps · \(snapshot.range.start.startDate().formatted(date: .abbreviated, time: .omitted)) – \(snapshot.range.end.startDate().formatted(date: .abbreviated, time: .omitted))"
                        : "\(snapshot.app.displayName) · \(snapshot.range.start.startDate().formatted(date: .abbreviated, time: .omitted)) – \(snapshot.range.end.startDate().formatted(date: .abbreviated, time: .omitted))"
                    )
            } else if model.isRefreshing {
                ProgressView(model.isAllApps ? "Loading all apps data…" : "Loading \(model.selectedApp?.displayName ?? "data")…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No Data Yet", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("Refresh to load the latest numbers for \(model.isAllApps ? "all apps" : (model.selectedApp?.displayName ?? "this app")).")
                } actions: {
                    Button("Refresh") { Task { await model.refresh() } }
                }
            }
        }
        .navigationTitle(section.title)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = model.refreshError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.multicolor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.yellow.opacity(0.15))
            }
        }
    }

    @ViewBuilder
    private func content(snapshot: DashboardSnapshot, brief: AppBrief) -> some View {
        switch section {
        case .overview: OverviewView(snapshot: snapshot, brief: brief)
        case .acquisition: AcquisitionView(snapshot: snapshot, brief: brief)
        case .engagement: EngagementView(snapshot: snapshot, brief: brief)
        case .stability: StabilityView(snapshot: snapshot, brief: brief)
        case .reviews: ReviewsView(snapshot: snapshot, brief: brief)
        case .brief: BriefView(snapshot: snapshot, brief: brief)
        }
    }
}

private struct OnboardingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Connect Your Apps", systemImage: "safari")
        } description: {
            Text("Add an App Store Connect API key and, optionally, a Google service account. Then import your apps to see downloads, engagement, stability, and reviews in one place.")
        } actions: {
            SettingsLink {
                Text("Open Settings…")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
