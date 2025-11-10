//
//  JobRow.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import MapKit
import CoreLocation

struct JobRow: View {
    let job: Job
    var onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.title)
                    .font(.headline)
                    .foregroundStyle(TBTheme.title)
                if job.isPremiumLead { BadgeView(text: "Premium", icon: "star.fill") }
                if !job.isConfirmed { BadgeView(text: "Tentative", icon: "questionmark.circle") }
            }

            HStack(spacing: 10) {
                Label(job.clientName, systemImage: "person")
                Text("•")
                Label(job.trade.rawValue.capitalized, systemImage: "wrench.and.screwdriver")
            }
            .font(.subheadline)
            .foregroundStyle(TBTheme.subtext)

            HStack(spacing: 12) {
                Label(job.scheduledStart.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                Label("\(Int(job.estimatedHours))h", systemImage: "hourglass")
                Label(currency(job.pay), systemImage: "sterlingsign.circle")
            }
            .font(.subheadline)
            .foregroundStyle(TBTheme.subtext)

            HStack {
                if job.address.coordinate != nil { MapSnapshot(address: job.address) }
                VStack(alignment: .leading) {
                    Text(job.address.line1).lineLimit(1).foregroundStyle(TBTheme.title)
                    Text("\(job.address.city), \(job.address.postcode)")
                        .font(.footnote)
                        .foregroundStyle(TBTheme.subtext)
                }
                Spacer()
                Button("Add to Calendar", action: onExport)
                    .buttonStyle(.borderedProminent)
                    .tint(TBTheme.brand)
            }
        }
        .padding(.vertical, 8)
    }
}

