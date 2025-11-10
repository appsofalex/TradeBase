//
//  MarketplaceView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import Observation

struct MarketplaceView: View {
    @Environment(AppState.self) private var state
    @State private var showingFilters = false

    var body: some View {
        @Bindable var bindableState = state

        NavigationStack {
            ZStack { TBTheme.gradient.ignoresSafeArea(); content }
                .navigationTitle("Find Work")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingFilters = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await state.refreshLeads() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
        }
        .sheet(isPresented: $showingFilters) {
            FilterSheet(
                filter: $bindableState.marketFilter,
                onApply: { Task { await state.refreshLeads() } }
            )
        }
    }

    @ViewBuilder private var content: some View {
        if state.leads.isEmpty {
            EmptyStateView(title: "No leads found",
                           subtitle: "Try widening your radius or trade types.",
                           icon: "mappin.and.ellipse")
        } else {
            List {
                ForEach(state.leads) { lead in
                    LeadCard(lead: lead, isPremium: state.profile.isPremium)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

