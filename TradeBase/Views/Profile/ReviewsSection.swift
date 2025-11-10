//
//  ReviewsSection.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct ReviewsSection: View {
    let reviews: [Review]
    var title: String = "Reviews"

    var body: some View {
        SectionCard(title: title, icon: "star.leadinghalf.filled") {
            ForEach(reviews) { r in
                VStack(alignment: .leading) {
                    HStack {
                        Stars(rating: r.rating)
                        Spacer()
                        Text(r.date, style: .date).foregroundStyle(.secondary).font(.footnote)
                    }
                    Text(r.text)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct PremiumPanel: View {
    var isPremium: Bool
    var onUpgradeTap: () -> Void = {}

    var body: some View {
        SectionCard(title: "TradeBase Premium", icon: "bolt.badge.a") {
            if isPremium {
                Label("You're Premium — priority leads, verified badge, instant booking.",
                      systemImage: "checkmark.seal.fill")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Priority in local searches", systemImage: "arrow.up.circle")
                    Label("Verified badge", systemImage: "checkmark.seal")
                    Label("Instant booking", systemImage: "bolt.fill")
                    Button("Upgrade — £9.99/mo") { onUpgradeTap() }
                        .buttonStyle(.borderedProminent)
                        .tint(TBTheme.brand)
                }
            }
        }
    }
}

