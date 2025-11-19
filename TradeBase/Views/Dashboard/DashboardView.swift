//
//  DashboardView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import EventKit
import EventKitUI
import MapKit

struct DashboardView: View {
    @Environment(\.appState) private var state
    @Environment(\.customerJobListingStore) private var store
    @Environment(\.switchTradesTab) private var switchTab

    @State private var calendarAccessDenied = false
    @State private var showMessageHub = false

    @State private var showWelcomePill = false
    @State private var autoHideTask: Task<Void, Never>? = nil
    private let pillExpandedWidth: CGFloat = 220

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Your Schedule")
                        .tbLargeHeader()

                    content
                        .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        toggleWelcomePill()
                    } label: {
                        HStack(spacing: 8) {
                            Image("logowithoutbg")
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 24)

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.black.opacity(0.35))
                                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                                Text("Welcome to TradeBase!")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 24)
                            }
                            .frame(width: showWelcomePill ? pillExpandedWidth : 0, height: 28)
                            .clipped()
                            .transition(.opacity)
                        }
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, alignment: .center)
                        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: showWelcomePill)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Welcome to TradeBase")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showMessageHub = true
                    } label: {
                        Image(systemName: "bell")
                            .overlay(alignment: .topTrailing) {
                                if state.unreadMessageCount > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 9, height: 9)
                                        .padding(.top, -2)
                                        .padding(.trailing, -4)
                                        .zIndex(1)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .accessibilityLabel("Messages")
                }
            }
            .background(
                NavigationLink(isActive: $showMessageHub) {
                    MessageHubView()
                        .environment(\.appState, state)
                } label: { EmptyView() }
                .hidden()
            )
        }
        .task {
            await state.refreshUnreadCount()
        }
        .alert("Calendar Access Denied", isPresented: $calendarAccessDenied) {
            Button("OK", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Please allow calendar access in Settings to add jobs to your calendar.")
        }
    }

    @ViewBuilder private var content: some View {
        let scheduled: [MarketplaceLead] = state.scheduledLeads(from: state.leads)

        if scheduled.isEmpty {
            ScrollView {
                VStack(spacing: 16) {
                    EmptyStateView(title: "No jobs lined up yet",
                                   subtitle: "Look for extra work in the Leads tab.",
                                   icon: "calendar.badge.exclamationmark")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)

                    Button {
                        switchTab(.leads)
                    } label: {
                        Text("View Leads")
                            .font(.headline)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(TBTheme.brand))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await state.load() }
        } else {
            List {
                ForEach(scheduled) { lead in
                    NavigationLink {
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
                        // Force system destructive red explicitly to override any inherited TabView tint.
                        Button(role: .destructive) {
                            state.removeFromSchedule(id: lead.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        .tint(.red)

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
                        Button(role: .destructive) {
                            state.removeFromSchedule(id: lead.id)
                        } label: {
                            Label("Remove from schedule", systemImage: "trash")
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
            .refreshable { await state.load() }
        }
    }

    // MARK: - Helpers copied from LeadsView

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
            if let url = firstRenderablePhotoURL(in: lead.photoURLs),
               let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                CategoryTile(trade: lead.category)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
        .accessibilityLabel(lead.category?.displayName ?? "Job")
    }

    private func firstRenderablePhotoURL(in urls: [URL]) -> URL? {
        for url in urls {
            if UIImage(contentsOfFile: url.path) != nil { return url }
        }
        return nil
    }

    private func budgetSummary(for lead: MarketplaceLead) -> String {
        let sym = CurrencyCatalog.symbol(for: lead.currency)
        switch lead.budgetType {
        case .quote:
            return "Quote requested"
        case .fixed:
            if let min = lead.budgetMin { return "\(sym)\(min as NSNumber)" }
            return "\(sym)—"
        case .hourly:
            if let min = lead.budgetMin { return "\(sym)\(min as NSNumber)/hr" }
            return "\(sym)—/hr"
        case .range:
            let minS = lead.budgetMin.map { "\($0 as NSNumber)" } ?? "—"
            let maxS = lead.budgetMax.map { "\($0 as NSNumber)" } ?? "—"
            return "\(sym)\(minS) – \(sym)\(maxS)"
        }
    }

    private func shareLead(_ lead: MarketplaceLead) {
        let text = "Job Lead: \(lead.title) in \(lead.location.city) \(lead.location.postcode)"
        let avc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            root.present(avc, animated: true, completion: nil)
        }
    }

    private func toggleWelcomePill() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showWelcomePill.toggle()
        }
        autoHideTask?.cancel()
        if showWelcomePill {
            autoHideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    showWelcomePill = false
                }
            }
        } else {
            autoHideTask = nil
        }
    }
}
