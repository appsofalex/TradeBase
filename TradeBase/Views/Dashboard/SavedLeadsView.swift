import SwiftUI

struct SavedLeadsView: View {
    @Environment(AppState.self) private var state
    var onClose: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()
                let saved = state.leads.filter { state.isLeadSaved($0.id) }
                if saved.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 44))
                            .foregroundStyle(TBTheme.subtext)
                        Text("No saved leads")
                            .font(.title3.bold())
                            .foregroundStyle(TBTheme.title)
                        Text("Tap the bookmark on any lead to save it here.")
                            .foregroundStyle(TBTheme.subtext)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(saved) { lead in
                            NavigationLink {
                                LeadDetailView(lead: lead)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bookmark.fill")
                                        .foregroundStyle(TBTheme.brand)
                                    VStack(alignment: .leading) {
                                        Text(lead.title.isEmpty ? "Untitled job" : lead.title)
                                            .font(.headline)
                                        Text("\(lead.location.city) \(lead.location.postcode)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    state.toggleSave(lead: lead)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}
