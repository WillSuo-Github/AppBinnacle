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
                    MetricTile(title: "New Reviews", value: summary.count.formatted(), change: MetricChange(summary.count, summary.previousCount))
                    MetricTile(title: "Average Rating", value: summary.averageRating.map { Format.number($0) + "★" } ?? "—",
                               caption: "New reviews in this period")
                    MetricTile(title: "Rated 1–2★", value: summary.lowRatingCount.formatted(), caption: "In this period")
                }

                ChartCard(title: "Rating Distribution", subtitle: "Latest \(reviews.count) reviews") {
                    Chart(distribution(reviews), id: \.stars) { bucket in
                        BarMark(x: .value("Reviews", bucket.count), y: .value("Rating", "\(bucket.stars)★"))
                            .foregroundStyle(bucket.stars <= 2 ? Color.red : (bucket.stars == 3 ? Color.orange : Color.yellow))
                            .annotation(position: .trailing) {
                                Text(bucket.count.formatted()).font(.caption).foregroundStyle(.secondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 150)
                }

                HStack {
                    Text("Latest Reviews").font(.headline)
                    Spacer()
                    Picker("Rating", selection: $filter) {
                        ForEach(RatingFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                }

                let visible = reviews.filter { filter.includes($0.rating) }
                if visible.isEmpty {
                    Text("No reviews match this filter.").foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
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
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    StarRating(rating: review.rating)
                    Text(review.title.isEmpty ? "Untitled" : review.title).font(.body.weight(.semibold))
                    Spacer()
                    if isInPeriod {
                        Text("This period")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.12), in: Capsule())
                    }
                }
                if !review.body.isEmpty {
                    Text(review.body).textSelection(.enabled)
                }
                // Reviews are grouped by App Store reporting day (Pacific Time), like sales.
                Text("\(review.reviewerNickname) · \(AcquisitionView.countryName(review.territory)) · \(review.day.startDate().formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
