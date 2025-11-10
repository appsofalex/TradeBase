//
//  ReviewsListView.swift
//  TradeBase
//
//  Simple destination that shows all reviews for the current profile.
//

import SwiftUI

struct ReviewsListView: View {
    // Instead of receiving a snapshot, read live state so refresh updates are reflected.
    // Also support an optional injected reviews array for backward compatibility with callers.
    @Environment(AppState.self) private var state

    // Back-compat: allow passing reviews explicitly. If nil, use state.profile.reviews.
    var reviews: [Review]? = nil

    // NEW: Identify if this screen is shown from the customer area.
    // Default is false so tradesperson flows are unaffected.
    var isCustomerContext: Bool = false

    // Resolve the reviews to display
    private var resolvedReviews: [Review] {
        reviews ?? state.profile.reviews as! [Review]
    }

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()

            if resolvedReviews.isEmpty {
                // Wrap in ScrollView so pull-to-refresh is available when empty
                ScrollView {
                    VStack(spacing: 12) {
                        Image(systemName: "star.leadinghalf.filled")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("None yet!")
                            .font(.title3.bold())
                        Text(emptyStateLine)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                .refreshable {
                    await state.refreshProfileFromCloud()
                }
            } else {
                List {
                    Section {
                        ForEach(resolvedReviews) { r in
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
                .refreshable {
                    await state.refreshProfileFromCloud()
                }
            }
        }
        .navigationTitle("Reviews")
    }

    // Unified wording across customers and tradespeople.
    private var emptyStateLine: String {
        "When reviews are posted, they'll appear here."
    }
}
