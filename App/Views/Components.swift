import SwiftUI

/// Reusable Apple-native card background with subtle material, hairline border, and gentle drop shadow.
struct AppleCardBackground: ViewModifier {
    var cornerRadius: CGFloat = 14
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color(nsColor: .controlBackgroundColor).opacity(0.72)
                          : Color.white.opacity(0.85))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.black.opacity(0.06),
                        lineWidth: 0.75
                    )
            }
            .shadow(
                color: colorScheme == .dark
                ? Color.black.opacity(0.28)
                : Color.black.opacity(0.04),
                radius: 8, x: 0, y: 2
            )
    }
}

extension View {
    func appleCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(AppleCardBackground(cornerRadius: cornerRadius))
    }
}

/// A scrolling dashboard page with consistent spacing and native macOS background tone.
struct DashboardPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var change: MetricChange?
    var caption: String?
    var higherIsBetter = true
    var systemImage: String? = nil
    var accentColor: Color = .accentColor
    var action: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .onHover { isHovered = $0 }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 24, height: 24)
                        .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isHovered ? accentColor : Color.secondary.opacity(0.35))
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
            }

            Spacer(minLength: 8)

            // Primary Metric Value
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            // Footer (Fixed 22pt height so all cards align perfectly)
            HStack(alignment: .center, spacing: 6) {
                if let change {
                    ChangeLabel(change: change, higherIsBetter: higherIsBetter)
                }
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 22, alignment: .leading)
        }
        .padding(14)
        .frame(height: 116)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appleCard(cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isHovered ? accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
    }
}

struct ChangeLabel: View {
    var change: MetricChange
    var higherIsBetter = true

    var body: some View {
        if let percent = change.changePercent {
            let isUnchanged = abs(percent) < 0.05
            let improved = higherIsBetter ? percent >= 0 : percent <= 0
            let badgeColor: Color = isUnchanged ? .secondary : (improved ? .green : .red)
            let iconName: String = isUnchanged ? "minus" : (percent >= 0 ? "arrow.up.right" : "arrow.down.right")

            HStack(spacing: 3) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .bold))
                Text(isUnchanged ? "0.0%" : Format.signedPercent(percent))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12), in: Capsule())
            .foregroundStyle(badgeColor)
        } else {
            HStack(spacing: 3) {
                Text("Prev: \(change.previous.formatted())")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1), in: Capsule())
            .foregroundStyle(.secondary)
        }
    }
}

struct MetricGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
            content
        }
    }
}

struct ChartCard<Content: View>: View {
    var title: String
    var subtitle: String?
    var systemImage: String? = nil
    var accentColor: Color = .accentColor
    var action: (() -> Void)? = nil
    var actionLabel: String = "View Details"
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 24, height: 24)
                        .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                if let action {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Text(actionLabel)
                                .font(.caption.weight(.medium))
                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appleCard(cornerRadius: 14)
    }
}

/// Explains why a data source has nothing to show and how to fix it.
struct SourceUnavailableView: View {
    var status: SourceStatus?
    var source: DataSource

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: status?.state == .failed ? "exclamationmark.triangle.fill" : "link.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(status?.state == .failed ? Color.red : Color.accentColor)
            Text(title)
                .font(.headline)
            Text(status?.detail ?? "Refresh to load \(source.title).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if status?.state != .failed {
                SettingsLink { Text("Configure in Settings…") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(24)
        .appleCard(cornerRadius: 14)
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
    var updatedAt: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label("Connected Telemetry Sources", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if let updatedAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text("Updated \(updatedAt.formatted(.relative(presentation: .named)))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 10) {
                ForEach(sources, id: \.source) { status in
                    SourcePill(status: status)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .appleCard(cornerRadius: 12)
    }
}

struct SourcePill: View {
    let status: SourceStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(status.source.shortTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(statusColor.opacity(0.2), lineWidth: 0.75))
        .help(status.detail ?? "\(status.source.title): \(status.state.rawValue)")
    }

    private var statusColor: Color {
        switch status.state {
        case .ok: return .green
        case .notConfigured: return .secondary
        case .failed: return .red
        }
    }
}

extension DataSource {
    var shortTitle: String {
        switch self {
        case .appStoreSales: return "Sales & Downloads"
        case .appStoreReviews: return "App Store Reviews"
        case .googleAnalytics: return "Google Analytics"
        case .crashlytics: return "Firebase Crashlytics"
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
