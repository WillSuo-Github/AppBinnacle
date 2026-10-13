import SwiftUI

/// A scrolling dashboard page with consistent spacing.
struct DashboardPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var change: MetricChange?
    var caption: String?
    var higherIsBetter = true

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let change {
                    ChangeLabel(change: change, higherIsBetter: higherIsBetter)
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChangeLabel: View {
    var change: MetricChange
    var higherIsBetter = true

    var body: some View {
        if let percent = change.changePercent {
            let improved = higherIsBetter ? percent >= 0 : percent <= 0
            Label {
                Text("\(Format.signedPercent(percent)) vs previous")
            } icon: {
                Image(systemName: percent >= 0 ? "arrow.up.right" : "arrow.down.right")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(abs(percent) < 1 ? Color.secondary : (improved ? Color.green : Color.red))
        } else {
            Text("Previous: \(change.previous.formatted())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MetricGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            content
        }
    }
}

struct ChartCard<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Explains why a data source has nothing to show and how to fix it.
struct SourceUnavailableView: View {
    var status: SourceStatus?
    var source: DataSource

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: status?.state == .failed ? "exclamationmark.triangle" : "link.badge.plus")
        } description: {
            Text(status?.detail ?? "Refresh to load \(source.title).")
        } actions: {
            if status?.state != .failed {
                SettingsLink { Text("Open Settings…") }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var title: String {
        switch status?.state {
        case .failed: return "\(source.title) Didn’t Load"
        case .notConfigured: return "Connect \(source.title)"
        default: return "No \(source.title) Data"
        }
    }
}

struct SourceStatusList: View {
    var sources: [SourceStatus]

    var body: some View {
        GroupBox("Data Sources") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sources, id: \.source) { status in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: symbol(status.state))
                            .foregroundStyle(color(status.state))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.source.title)
                            if let detail = status.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func symbol(_ state: SourceStatus.State) -> String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .notConfigured: return "minus.circle"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(_ state: SourceStatus.State) -> Color {
        switch state {
        case .ok: return .green
        case .notConfigured: return .secondary
        case .failed: return .red
        }
    }
}

struct StarRating: View {
    var rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
            }
        }
        .font(.caption)
        .foregroundStyle(rating <= 2 ? Color.red : (rating == 3 ? Color.orange : Color.yellow))
        .accessibilityLabel("\(rating) out of 5 stars")
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension DayRange {
    var shortLabel: String {
        "\(start.startDate().formatted(.dateTime.month(.abbreviated).day())) – \(end.startDate().formatted(.dateTime.month(.abbreviated).day()))"
    }
}
