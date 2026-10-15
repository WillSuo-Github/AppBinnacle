import SwiftUI

struct SidebarSyncFooter: View {
    @Environment(DashboardModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)

            VStack(alignment: .leading, spacing: 10) {
                // Header with Auto-refresh interval menu + manual Refresh button
                HStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("Data Sync")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }

                    Spacer(minLength: 0)

                    // Quick Auto-refresh interval menu
                    Menu {
                        ForEach(AutoRefreshInterval.allCases) { interval in
                            Button {
                                model.autoRefreshInterval = interval
                            } label: {
                                HStack {
                                    Text(interval.title)
                                    if model.autoRefreshInterval == interval {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.system(size: 8))
                            Text(model.autoRefreshInterval.shortLabel)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Set automatic background refresh interval (current: \(model.autoRefreshInterval.title))")

                    // Manual Refresh button
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        HStack(spacing: 3) {
                            if model.isRefreshing {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            Text(model.isRefreshing ? "Syncing…" : "Refresh")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(model.isRefreshing ? Color.secondary : Color.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.configuration.apps.isEmpty || model.isRefreshing)
                    .help("Refresh all telemetry connections (⌘R)")
                }

                // Platform Rows
                VStack(spacing: 6) {
                    syncRow(
                        title: "Sales & Trends",
                        icon: "apple.logo",
                        iconColor: .blue,
                        status: model.snapshot?.status(of: .appStoreSales),
                        customTime: salesCustomTime
                    )

                    syncRow(
                        title: "App Store Reviews",
                        icon: "star.bubble.fill",
                        iconColor: .orange,
                        status: model.snapshot?.status(of: .appStoreReviews),
                        customTime: nil
                    )

                    syncRow(
                        title: "Google Analytics",
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .indigo,
                        status: model.snapshot?.status(of: .googleAnalytics),
                        customTime: nil
                    )

                    syncRow(
                        title: "Crashlytics",
                        icon: "bolt.heart.fill",
                        iconColor: .pink,
                        status: model.snapshot?.status(of: .crashlytics),
                        customTime: nil
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var salesCustomTime: String? {
        if let sales = model.snapshot?.sales, let range = model.snapshot?.salesRange {
            if sales.throughDay < range.end {
                return "Through \(sales.throughDay.startDate().formatted(.dateTime.month(.abbreviated).day()))"
            }
        }
        return nil
    }

    private func syncRow(
        title: String,
        icon: String,
        iconColor: Color,
        status: SourceStatus?,
        customTime: String?
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDot(status?.state))
                .frame(width: 5, height: 5)

            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 14)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(formatTime(status: status, customTime: customTime))
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(tooltip(title: title, status: status))
    }

    private func formatTime(status: SourceStatus?, customTime: String?) -> String {
        guard let status else { return "—" }
        switch status.state {
        case .ok:
            if let customTime { return customTime }
            if let date = status.lastSyncedAt ?? model.snapshot?.generatedAt {
                return formatShortRelative(date)
            }
            return "Active"
        case .notConfigured:
            return "Off"
        case .failed:
            return "Failed"
        }
    }

    private func tooltip(title: String, status: SourceStatus?) -> String {
        guard let status else { return "\(title): No data" }
        var parts: [String] = ["\(title): \(status.state.rawValue)"]
        if let date = status.lastSyncedAt ?? model.snapshot?.generatedAt {
            parts.append("Last fetched: \(date.formatted(date: .abbreviated, time: .standard))")
        }
        if let detail = status.detail {
            parts.append(detail)
        }
        return parts.joined(separator: "\n")
    }

    private func statusDot(_ state: SourceStatus.State?) -> Color {
        switch state {
        case .ok: return .green
        case .failed: return .red
        case .notConfigured: return .secondary.opacity(0.4)
        case .none: return .secondary.opacity(0.3)
        }
    }

    private func formatShortRelative(_ date: Date) -> String {
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let mins = max(1, Int(seconds / 60))
            return "\(mins)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            return date.formatted(date: .numeric, time: .omitted)
        }
    }
}
