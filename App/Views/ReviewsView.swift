import Charts
import SwiftUI

struct ReviewsView: View {
    let snapshot: DashboardSnapshot
    let brief: AppBrief
    @State private var filter = RatingFilter.all

    enum RatingFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case critical = "1–2★"
        case neutral = "3★"
        case positive = "4–5★"

        var id: String { rawValue }

        func includes(_ rating: Int) -> Bool {
            switch self {
            case .all: return true
            case .critical: return rating <= 2
            case .neutral: return rating == 3
            case .positive: return rating >= 4
            }
        }
    }

    var body: some View {
        if let reviews = snapshot.reviews, let summary = brief.reviews {
            let totalReviewsCount = max(1, summary.count)
            let positiveCount = reviews.filter { $0.rating >= 4 }.count
            let criticalCount = summary.lowRatingCount
            let positiveRate = Double(positiveCount) / Double(totalReviewsCount)
            let criticalRate = Double(criticalCount) / Double(totalReviewsCount)

            DashboardPage {
                HStack(alignment: .center) {
                    Label("App Store Customer Feedback & Sentiment", systemImage: "star.bubble.fill")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    #if os(macOS)
                    Button {
                        let filename = "AppBinnacle-Reviews-\(snapshot.app.displayName).csv"
                        SaveFileDialog.save(filename: filename, content: ReportExporter.exportReviewsCSV(snapshot: snapshot))
                    } label: {
                        Label("Export Reviews CSV", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Export all customer reviews to CSV")
                    #endif
                }

                MetricGrid {
                    MetricTile(
                        title: "Total Reviews",
                        value: summary.count.formatted(),
                        change: MetricChange(summary.count, summary.previousCount),
                        systemImage: "star.bubble.fill",
                        accentColor: .orange
                    )
                    MetricTile(
                        title: "Average Rating",
                        value: summary.averageRating.map { Format.number($0) + "★" } ?? "—",
                        caption: "Across current period reviews",
                        systemImage: "star.fill",
                        accentColor: .yellow
                    )
                    MetricTile(
                        title: "Positive Sentiment",
                        value: summary.count > 0 ? "\(String(format: "%.0f%%", positiveRate * 100))" : "—",
                        caption: "\(positiveCount) rated 4–5★",
                        systemImage: "hand.thumbsup.fill",
                        accentColor: .green
                    )
                    MetricTile(
                        title: "Critical Feedback",
                        value: summary.count > 0 ? "\(String(format: "%.0f%%", criticalRate * 100))" : "—",
                        caption: "\(criticalCount) rated 1–2★",
                        higherIsBetter: false,
                        systemImage: "hand.thumbsdown.fill",
                        accentColor: .red
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    ChartCard(
                        title: "Rating Distribution",
                        subtitle: "Breakdown of latest \(reviews.count) reviews",
                        systemImage: "chart.bar.xaxis",
                        accentColor: .orange
                    ) {
                        Chart(distribution(reviews), id: \.stars) { bucket in
                            BarMark(x: .value("Reviews", bucket.count), y: .value("Rating", "\(bucket.stars)★"))
                                .foregroundStyle(bucket.stars <= 2 ? Color.red : (bucket.stars == 3 ? Color.orange : Color.yellow))
                                .cornerRadius(3)
                                .annotation(position: .trailing) {
                                    Text(bucket.count.formatted()).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 150)
                    }

                    ChartCard(
                        title: "Feedback by Territory",
                        subtitle: "Top reviewing markets",
                        systemImage: "globe.europe.africa.fill",
                        accentColor: .blue
                    ) {
                        let territories = topTerritories(reviews)
                        if territories.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                                Text("No regional review data available.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(territories, id: \.code) { item in
                                    HStack {
                                        Text(AcquisitionView.flag(for: item.code))
                                        Text(AcquisitionView.countryName(item.code))
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(item.count) reviews")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("\(String(format: "%.1f", item.avgRating))★")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.yellow)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                HStack(alignment: .center) {
                    Label("Latest Reviews", systemImage: "quote.bubble.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Picker("Rating Filter", selection: $filter) {
                        ForEach(RatingFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                }

                let visible = reviews.filter { filter.includes($0.rating) }
                if visible.isEmpty {
                    VStack(spacing: 8) {
                        Text("No reviews match this filter.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .appleCard(cornerRadius: 12)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visible) { review in
                            ReviewRow(review: review, isInPeriod: snapshot.range.contains(review.day))
                        }
                    }
                }
            }
        } else {
            SourceUnavailableView(status: snapshot.status(of: .appStoreReviews), source: .appStoreReviews)
        }
    }

    private func distribution(_ reviews: [CustomerReview]) -> [(stars: Int, count: Int)] {
        (1...5).reversed().map { stars in (stars, reviews.filter { $0.rating == stars }.count) }
    }

    private func topTerritories(_ reviews: [CustomerReview]) -> [(code: String, count: Int, avgRating: Double)] {
        let grouped = Dictionary(grouping: reviews, by: \.territory)
        return grouped.map { code, list in
            let avg = Double(list.reduce(0) { $0 + $1.rating }) / Double(list.count)
            return (code: code, count: list.count, avgRating: avg)
        }
        .sorted { $0.count > $1.count }
        .prefix(4)
        .map { $0 }
    }
}

private struct ReviewRow: View {
    let review: CustomerReview
    let isInPeriod: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                StarRating(rating: review.rating)
                Text(review.title.isEmpty ? "Untitled" : review.title)
                    .font(.body.weight(.semibold))
                Spacer()
                if isInPeriod {
                    Text("This period")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            if !review.body.isEmpty {
                Text(review.body)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 6) {
                Text(AcquisitionView.flag(for: review.territory))
                Text("\(review.reviewerNickname) · \(AcquisitionView.countryName(review.territory)) · \(review.day.startDate().formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appleCard(cornerRadius: 12)
    }
}
