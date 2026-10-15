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
            DashboardPage {
                MetricGrid {
                    MetricTile(
                        title: "New Reviews",
                        value: summary.count.formatted(),
                        change: MetricChange(summary.count, summary.previousCount),
                        systemImage: "star.bubble.fill",
                        accentColor: .orange
                    )
                    MetricTile(
                        title: "Average Rating",
                        value: summary.averageRating.map { Format.number($0) + "★" } ?? "—",
                        caption: "New reviews in this period",
                        systemImage: "star.fill",
                        accentColor: .yellow
                    )
                    MetricTile(
                        title: "Rated 1–2★",
                        value: summary.lowRatingCount.formatted(),
                        caption: "In this period",
                        higherIsBetter: false,
                        systemImage: "hand.thumbsdown.fill",
                        accentColor: .red
                    )
                }

                ChartCard(
                    title: "Rating Distribution",
                    subtitle: "Latest \(reviews.count) reviews",
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
            Text("\(review.reviewerNickname) · \(AcquisitionView.countryName(review.territory)) · \(review.day.startDate().formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appleCard(cornerRadius: 12)
    }
}
