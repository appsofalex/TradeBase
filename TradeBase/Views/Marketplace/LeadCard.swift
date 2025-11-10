//
//  LeadCard.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import MapKit
import CoreLocation

struct LeadCard: View {
    let lead: MarketplaceLead
    var isPremium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lead.title.isEmpty ? "Untitled job" : lead.title)
                    .font(.headline)
                    .foregroundStyle(TBTheme.title)
                if lead.isUrgent {
                    BadgeView(text: "Urgent", icon: "exclamationmark.triangle.fill")
                }
            }

            HStack(spacing: 10) {
                Label((lead.category?.rawValue.capitalized ?? "General"), systemImage: "wrench.and.screwdriver")
                Text("•")
                let place = lead.location.city.isEmpty ? lead.location.postcode : lead.location.city
                Label(place, systemImage: "mappin.and.ellipse")
                Text("•")
                Label(budgetSummary(for: lead), systemImage: "sterlingsign.circle")
            }
            .font(.subheadline)
            .foregroundStyle(TBTheme.subtext)

            HStack {
                if lead.location.coordinate != nil { MapSnapshot(address: lead.location) }
                VStack(alignment: .leading) {
                    Text(lead.location.line1).lineLimit(1).foregroundStyle(TBTheme.title)
                    Text("\(lead.location.city)\(lead.location.city.isEmpty ? "" : " • ")posted \(relative(lead.createdAt))")
                        .font(.footnote)
                        .foregroundStyle(TBTheme.subtext)
                }
                Spacer()
                if isPremium {
                    Button("Priority Lead") { }
                        .buttonStyle(.borderedProminent).tint(TBTheme.brand)
                } else {
                    Button("Go Premium") { }
                        .buttonStyle(.bordered).tint(TBTheme.brand)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Local helpers

    private func budgetSummary(for lead: MarketplaceLead) -> String {
        switch lead.budgetType {
        case .quote:
            return "Quote requested"
        case .fixed:
            if let min = lead.budgetMin { return "\(lead.currency) \(min as NSNumber)" }
            return "\(lead.currency) —"
        case .hourly:
            if let min = lead.budgetMin { return "\(lead.currency) \(min as NSNumber)/hr" }
            return "\(lead.currency) —/hr"
        case .range:
            let minS = lead.budgetMin.map { "\($0 as NSNumber)" } ?? "—"
            let maxS = lead.budgetMax.map { "\($0 as NSNumber)" } ?? "—"
            return "\(lead.currency) \(minS) – \(lead.currency) \(maxS)"
        }
    }
}

// MARK: - Local helpers

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
}()

private func relative(_ date: Date, from reference: Date = Date()) -> String {
    relativeFormatter.localizedString(for: date, relativeTo: reference)
}
