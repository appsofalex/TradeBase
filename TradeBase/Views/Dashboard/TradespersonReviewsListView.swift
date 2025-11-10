//
//  TradespersonReviewsListView.swift
//  TradeBase
//
//  Shows reviews on a tradesperson profile. Empty-state text references customers.
//

import SwiftUI

struct TradespersonReviewsListView: View {
    @Environment(AppState.self) private var state

    // Optional back-compat injection; if nil we use state.profile.reviews.
    var reviews: [Review]? = nil

    private var resolvedReviews: [Review] {
        reviews ?? state.profile.reviews as! [Review]
    }

    var body: some View {
        ReviewsListView(
            reviews: resolvedReviews,
            isCustomerContext: false // tradesperson context => "customers" empty-state text
        )
        .navigationTitle("Reviews")
    }
}
