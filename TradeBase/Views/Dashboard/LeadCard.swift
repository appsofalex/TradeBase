//
//  LeadCard.swift
//  TradeBase
//

import SwiftUI

struct DashboardLeadCard: View {
    let lead: MarketplaceLead
    var isPremium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lead.title).font(.headline)
                Spacer()
                if lead.isVerified {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
                if lead.isInstantBook {
                    Image(systemName: "bolt.fill").foregroundStyle(TBTheme.brand)
                }
            }
            Text("\(lead.trade.rawValue.capitalized) • \(lead.address.city)")
                .foregroundStyle(.secondary)
            HStack {
                Text("£\(lead.pay.amount) \(lead.pay.currency)")
                Spacer()
                Text(String(format: "%.1f km", lead.distanceKm))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
