import SwiftUI

struct HiddenLeadsView: View {
    @Environment(AppState.self) private var state
    var onClose: (() -> Void)? = nil

    // Derive hidden leads from available state (hiddenLeadIDs is [String] of UUID strings)
    private var hiddenLeads: [MarketplaceLead] {
        let hiddenSet = Set(state.hiddenLeadIDs.map { $0.lowercased() })
        return state.leads.filter { hiddenSet.contains($0.id.uuidString.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()
                if hiddenLeads.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(TBTheme.subtext)
                        Text("No hidden jobs")
                            .font(.title3.bold())
                            .foregroundStyle(TBTheme.title)
                        Text("You can hide jobs from the Leads list. They’ll show up here.")
                            .foregroundStyle(TBTheme.subtext)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(hiddenLeads) { lead in
                            HStack(spacing: 12) {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text(lead.title.isEmpty ? "Untitled job" : lead.title)
                                        .font(.headline)
                                    Text("\(lead.location.city) \(lead.location.postcode)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    state.unhideLead(id: lead.id)
                                } label: {
                                    Text("Unhide")
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                            }
                            .padding(.vertical, 6)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    state.unhideLead(id: lead.id)
                                } label: {
                                    Label("Unhide", systemImage: "eye")
                                }
                                .tint(.green)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Hidden")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !state.hiddenLeadIDs.isEmpty {
                        Button("Unhide All") {
                            state.unhideAllLeads()
                        }
                    }
                }
            }
        }
    }
}
