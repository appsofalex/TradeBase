//
//  CustomerReviewsListView.swift
//  TradeBase
//
//  Shows reviews on a customer profile. Empty-state text references tradespeople.
//

import SwiftUI

struct CustomerReviewsListView: View {
    @Environment(AppState.self) private var state

    // Optional back-compat injection; if nil we use state.profile.reviews.
    var reviews: [Review]? = nil

    private var resolvedReviews: [Review] {
        reviews ?? state.profile.reviews as! [Review]
    }

    var body: some View {
        ReviewsListRenderer(
            reviews: resolvedReviews,
            emptyLine: "When reviews are posted, they'll appear here.",
            refresh: { await state.refreshProfileFromCloud() }
        )
        .navigationTitle("Reviews")
    }
}

// MARK: - Shared renderer used by both customer and trades views

private struct ReviewsListRenderer: View {
    var reviews: [Review]
    var emptyLine: String
    var refresh: () async -> Void

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()

            if reviews.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        Image(systemName: "star.leadinghalf.filled")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("None yet!")
                            .font(.title3.bold())
                        Text(emptyLine)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                .refreshable { await refresh() }
            } else {
                List {
                    Section {
                        ForEach(reviews) { r in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Stars(rating: r.rating)
                                    Spacer()
                                    Text(r.date, style: .date)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text(r.text)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await refresh() }
            }
        }
    }
}
