import SwiftUI
import MapKit

// MARK: - Marketplace View

struct LeadsView: View {
    @Environment(AppState.self) private var state
    @State private var isRefreshing = false
    @State private var showingSaved = false
    @State private var showingHidden = false

    // Location picker sheet
    @State private var showingLocationPicker = false

    // NEW: Job type filter sheet
    @State private var showingFilterSheet = false

    // Always-pill control sizing
    @State private var pillTargetWidth: CGFloat = 140
    @State private var expandedNaturalWidth: CGFloat = 140
    @State private var hasInitializedPill = false

    // Fixed conservative cap so the right toolbar breathes (shorter than before)
    @State private var pillMaxWidth: CGFloat = 170

    // The text we will show in the pill
    private var pillText: String {
        let trimmed = state.leadsSearchLocation.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Location" }
        let def = AppState.LeadsSearchLocation(
            displayName: "London",
            latitude: 51.5074,
            longitude: -0.1278,
            city: "London",
            postcode: nil
        )
        return (state.leadsSearchLocation == def) ? "Location" : trimmed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Leads").tbLargeHeader()

                    content
                        .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingLocationPicker = true
                    } label: {
                        ZStack {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill")
                                    .imageScale(.medium)
                                    .foregroundStyle(TBTheme.brand)
                                Text(pillText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .contentTransition(.opacity)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(width: pillTargetWidth, height: 36, alignment: .center)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            )
                            .contentShape(Capsule())
                            .animation(hasInitializedPill ? .spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.2) : nil,
                                       value: pillTargetWidth)

                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill").imageScale(.medium)
                                Text(pillText.isEmpty ? "Location" : pillText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            let natural = max(geo.size.width, 60)
                                            expandedNaturalWidth = natural
                                            let clamped = min(max(natural, 80), pillMaxWidth)
                                            pillTargetWidth = clamped
                                        }
                                        .onChange(of: pillText) { _, _ in
                                            let natural = max(geo.size.width, 60)
                                            expandedNaturalWidth = natural
                                            let clamped = min(max(natural, 80), pillMaxWidth)
                                            if hasInitializedPill {
                                                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                                    pillTargetWidth = clamped
                                                }
                                            } else {
                                                pillTargetWidth = clamped
                                            }
                                        }
                                }
                            )
                            .opacity(0)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                        }
                        .frame(height: 36, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change location")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Filter by job type")
                    .accessibilityHint("Choose trades to filter leads")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSaved = true
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Saved leads")
                    .accessibilityHint("Shows your saved leads")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHidden = true
                    } label: {
                        Image(systemName: "eye.slash")
                    }
                    .accessibilityLabel("Hidden jobs")
                    .accessibilityHint("Shows your hidden jobs")
                }
            }
        }
        .sheet(isPresented: $showingSaved) {
            SavedLeadsView(onClose: { showingSaved = false })
        }
        .sheet(isPresented: $showingHidden) {
            HiddenLeadsView(onClose: { showingHidden = false })
        }
        .sheet(isPresented: $showingLocationPicker) {
            LeadsLocationPickerSheet(
                initialDisplayName: state.leadsSearchLocation.displayName,
                initialCoordinate: state.leadsSearchLocation.coordinate
            ) { result in
                state.leadsSearchLocation = AppState.LeadsSearchLocation(
                    displayName: result.displayName,
                    latitude: result.coordinate?.latitude,
                    longitude: result.coordinate?.longitude,
                    city: result.city,
                    postcode: result.postcode
                )
                hasInitializedPill = true
                Task { await refresh() }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            JobTypeFilterSheet(
                selectedTrades: Binding(
                    get: { state.marketFilter.selectedTrades },
                    set: { newValue in
                        state.marketFilter.selectedTrades = newValue
                    }
                ),
                onClose: { showingFilterSheet = false }
            )
        }
        .task {
            await refresh()
            await state.promptAndAutofillLeadsLocationIfNeeded()
            hasInitializedPill = true
        }
    }

    @ViewBuilder
    private var content: some View {
        let tradeFiltered: [MarketplaceLead] = {
            let selected = state.marketFilter.selectedTrades
            if selected.isEmpty {
                return state.leads
            } else {
                return state.leads.filter { lead in
                    guard let cat = lead.category else { return false }
                    return selected.contains(cat)
                }
            }
        }()

        // Normalize hidden IDs for consistent comparison
        let hiddenSet = Set(state.hiddenLeadIDs.map { $0.lowercased() })
        let visibleLeads = tradeFiltered.filter { !hiddenSet.contains($0.id.uuidString.lowercased()) }

        VStack(spacing: 8) {
            if !state.marketFilter.selectedTrades.isEmpty {
                HStack {
                    let names = state.marketFilter.selectedTrades.map { $0.displayName }.sorted()
                    let summary: String = {
                        if names.count <= 2 { return names.joined(separator: ", ") }
                        return "\(names.prefix(2).joined(separator: ", ")) + \(names.count - 2) more"
                    }()
                    Label(summary, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    Button("Clear") {
                        state.marketFilter.selectedTrades.removeAll()
                    }
                    .font(.footnote)
                    .foregroundStyle(TBTheme.brand)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            if visibleLeads.isEmpty {
                ScrollView {
                    VStack {
                        if #available(iOS 17.0, *) {
                            ContentUnavailableView("No leads match your filter",
                                                   systemImage: "line.3.horizontal.decrease.circle",
                                                   description: Text(state.marketFilter.selectedTrades.isEmpty
                                                                      ? "Newly posted jobs will show up here."
                                                                      : "Try clearing or changing the job type filters."))
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 44))
                                    .foregroundStyle(TBTheme.subtext)
                                Text("No leads match your filter")
                                    .font(.title3.bold())
                                    .foregroundStyle(TBTheme.title)
                                Text(state.marketFilter.selectedTrades.isEmpty
                                     ? "Newly posted jobs will show up here."
                                     : "Try clearing or changing the job type filters.")
                                    .foregroundStyle(TBTheme.subtext)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
                .scrollContentBackground(.hidden)
                .refreshable { await refresh() }
            } else {
                List {
                    ForEach(visibleLeads) { lead in
                        NavigationLink {
                            // Push detail view (no messaging environment pass-through anymore)
                            LeadDetailView(lead: lead)
                        } label: {
                            HStack(spacing: 12) {
                                leadThumbnail(lead)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(lead.title.isEmpty ? "Untitled job" : lead.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        if lead.isUrgent {
                                            Text("Urgent")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.red.opacity(0.2)))
                                        }
                                        Spacer()
                                        if state.isLeadSaved(lead.id) {
                                            Image(systemName: "bookmark.fill")
                                                .foregroundStyle(TBTheme.brand)
                                                .accessibilityHidden(true)
                                        }
                                    }

                                    Text(subtitleLine(for: lead))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    if let start = lead.startDate {
                                        Text("Start: \(start.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(budgetSummary(for: lead))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                state.toggleSave(lead: lead)
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            } label: {
                                Label(state.isLeadSaved(lead.id) ? "Unsave" : "Save",
                                      systemImage: state.isLeadSaved(lead.id) ? "bookmark.slash" : "bookmark")
                            }
                            .tint(TBTheme.brand)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                state.hideLead(id: lead.id)
                            } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                            Button {
                                shareLead(lead)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                state.toggleSave(lead: lead)
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            } label: {
                                Label(state.isLeadSaved(lead.id) ? "Unsave" : "Save",
                                      systemImage: state.isLeadSaved(lead.id) ? "bookmark.slash" : "bookmark")
                            }
                            Divider()
                            Button {
                                state.hideLead(id: lead.id)
                            } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                            Divider()
                            Button {
                                shareLead(lead)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await refresh() }
            }
        }
    }

    private func subtitleLine(for lead: MarketplaceLead) -> String {
        var tokens: [String] = []
        if let cat = lead.category { tokens.append(cat.displayName) }
        let addressTokens: [String] = {
            let lines = lead.location.formattedLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                return Array(lines.prefix(3))
            }
            var parts: [String] = []
            if !lead.location.city.isEmpty { parts.append(lead.location.city) }
            if !lead.location.postcode.isEmpty { parts.append(lead.location.postcode) }
            return parts
        }()
        tokens.append(contentsOf: addressTokens)
        return tokens.joined(separator: " • ")
    }

    private func leadThumbnail(_ lead: MarketplaceLead) -> some View {
        Group {
            if let url = lead.photoURLs.first,
               let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
    }

    private func budgetSummary(for: MarketplaceLead) -> String {
        let sym = CurrencyCatalog.symbol(for: `for`.currency)
        switch `for`.budgetType {
        case .quote:
            return "Quote requested"
        case .fixed:
            if let min = `for`.budgetMin { return "\(sym)\(min as NSNumber)" }
            return "\(sym)—"
        case .hourly:
            if let min = `for`.budgetMin { return "\(sym)\(min as NSNumber)/hr" }
            return "\(sym)—/hr"
        case .range:
            let minS = `for`.budgetMin.map { "\($0 as NSNumber)" } ?? "—"
            let maxS = `for`.budgetMax.map { "\($0 as NSNumber)" } ?? "—"
            return "\(sym)\(minS) – \(sym)\(maxS)"
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await state.refreshLeads()
    }

    private func shareLead(_ lead: MarketplaceLead) {
        let text = "Job Lead: \(lead.title) in \(lead.location.city) \(lead.location.postcode)"
        let avc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            root.present(avc, animated: true, completion: nil)
        }
    }
}

// Helper to allow conditional contentShape with different shapes
private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { self.pathBuilder = { rect in shape.path(in: rect) } }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

// MARK: - JobTypeFilterSheet

private struct JobTypeFilterSheet: View {
    @Binding var selectedTrades: Set<TradeType>
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var options: [TradeType] { TradeType.allCases.sorted { $0.displayName < $1.displayName } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedTrades.removeAll()
                    } label: {
                        HStack {
                            Text("All trades")
                            Spacer()
                            if selectedTrades.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(TBTheme.brand)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section("Select trades") {
                    ForEach(options) { trade in
                        Button {
                            if selectedTrades.contains(trade) {
                                selectedTrades.remove(trade)
                            } else {
                                selectedTrades.insert(trade)
                            }
                        } label: {
                            HStack {
                                Text(trade.displayName)
                                Spacer()
                                if selectedTrades.contains(trade) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(TBTheme.brand)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        onClose()
                    }
                }
            }
        }
    }
}
