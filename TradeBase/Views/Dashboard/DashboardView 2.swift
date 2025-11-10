//
//  DashboardView 2.swift
//  TradeBase
//

import SwiftUI

struct LegacyDashboardView: View {
    @Environment(\.appState) private var state
    @Environment(\.customerJobListingStore) private var store

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()
                content
            }
            .navigationTitle("Jobs")
        }
    }

    @ViewBuilder private var content: some View {
        // Use the current user's listings as “jobs”
        let ownerId = state.profile.id
        // Consider upcoming/scheduled work as active or inProgress
        let listings = store.all(for: ownerId).filter { $0.status == .active || $0.status == .inProgress }

        if listings.isEmpty {
            EmptyStateView(title: "No upcoming jobs",
                           subtitle: "Your confirmed and scheduled work will appear here.",
                           icon: "calendar.badge.clock")
        } else {
            List {
                ForEach(listings) { job in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(job.title.isEmpty ? "Untitled job" : job.title)
                                .font(.headline)
                            Spacer()
                            // Consider "active" as confirmed/posted
                            if job.status == .active || job.status == .inProgress {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        // Show category and city if available
                        HStack(spacing: 6) {
                            if let cat = job.category {
                                Text(cat.displayName)
                            }
                            if !job.location.city.isEmpty {
                                Text("• \(job.location.city)")
                            }
                        }
                        .foregroundStyle(.secondary)
                        .font(.subheadline)

                        // Start date if present
                        if let start = job.startDate {
                            Text(start, style: .date)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}
