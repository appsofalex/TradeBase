//
//  DashboardView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import EventKit
import EventKitUI

struct DashboardView: View {
    @Environment(\.appState) private var state
    @Environment(\.customerJobListingStore) private var store
    @State private var eventToEdit: Job? = nil
    @State private var calendarAccessDenied = false

    // Phase 2: Navigation to message hub
    @State private var showMessageHub = false

    // Logo pill state (mirrors CustomerHomeView)
    @State private var showWelcomePill = false
    @State private var autoHideTask: Task<Void, Never>? = nil
    private let pillExpandedWidth: CGFloat = 220

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    // Bubbly header aligned like Community (no extra horizontal padding)
                    Text("Your Schedule")
                        .tbLargeHeader()

                    // Main content below header
                    content
                        .padding(.top, 8)
                }
            }
            // Hide the system nav title so only our header shows
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                // Centered (principal) logo that expands to a welcome pill
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

                            // Animated-width pill (centered)
                            ZStack(alignment: .leading) {
                                Capsule()
                                    // Dark pill to match app’s navbar/dark blue look
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
                        // Ensure the whole thing stays centered in the principal area
                        .frame(maxWidth: .infinity, alignment: .center)
                        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: showWelcomePill)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Welcome to TradeBase")
                }

                // RIGHT-aligned bell
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
                                        .padding(.top, -2)      // move up into the gap
                                        .padding(.trailing, -4) // move right toward the ring, but not touching
                                        .zIndex(1)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .accessibilityLabel("Messages")
                }
            }
            // Replace sheet with a navigation push so we get the native back arrow.
            .background(
                NavigationLink(isActive: $showMessageHub) {
                    MessageHubView()
                        .environment(\.appState, state)
                } label: { EmptyView() }
                .hidden()
            )
        }
        // Best-effort: ensure unread count is up to date so the red dot appears promptly
        .task {
            await state.refreshUnreadCount()
        }
        .sheet(item: $eventToEdit) { job in
            EventEditView(job: job) { action in
                /*
                if action == .saved {
                    openCalendar(at: job.scheduledStart)
                }
                */
            }
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
        // Derive scheduled jobs from the user's listings
        let owner: UUID = state.profile.id
        // Only include jobs that are actually scheduled/accepted by the tradesperson.
        // Exclude `.active` because that represents a marketplace posting (a lead), not a scheduled job.
        let scheduledListings: [JobListing] = store.all(for: owner).filter { listing in
            listing.status == .inProgress || listing.status == .completed
        }

        // Map JobListing -> Job (best-effort mapping for display)
        let jobs: [Job] = scheduledListings.compactMap { (listing: JobListing) -> Job? in
            // Require a startDate to be schedulable; otherwise skip
            guard let start = listing.startDate else { return nil }
            let trade = listing.category ?? .generalBuilder
            let addr = listing.location
            // Approximate pay from budgetMin if available
            let payAmount: Decimal = listing.budgetMin ?? 0
            let money = Money(amount: payAmount, currency: listing.currency)
            return Job(
                id: UUID(),
                title: listing.title,
                clientName: "",
                trade: trade,
                scheduledStart: start,
                estimatedHours: 2,
                pay: money,
                address: addr,
                notes: nil,
                isConfirmed: listing.status == .inProgress || listing.status == .completed,
                isPremiumLead: false
            )
        }
        .sorted(by: { $0.scheduledStart < $1.scheduledStart })

        if jobs.isEmpty {
            // Wrap empty state in ScrollView so pull-to-refresh works
            ScrollView {
                EmptyStateView(title: "No jobs lined up yet",
                               subtitle: "Look for extra work in the Leads tab.",
                               icon: "calendar.badge.exclamationmark")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
            .refreshable { await state.load() }
        } else {
            List {
                ForEach(groupedByDay(jobs), id: \.0) { day, jobs in
                    Section {
                        ForEach(jobs) { job in
                            JobRow(job: job) {
                                Task { await presentEventEditor(for: job) }
                            }
                        }
                    } header: {
                        Text(day.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(TBTheme.offWhite)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await state.load() }
        }
    }

    private func groupedByDay(_ jobs: [Job]) -> [(Date, [Job])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: jobs) { cal.startOfDay(for: $0.scheduledStart) }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.scheduledStart < $1.scheduledStart }) }
    }

    private func presentEventEditor(for job: Job) async {
        let store = EKEventStore()
        do {
            try await store.requestFullAccessToEvents()
            await MainActor.run { eventToEdit = job }
        } catch {
            await MainActor.run { calendarAccessDenied = true }
        }
    }

    private func openCalendar(at date: Date) {
        let interval = date.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(interval)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Logo pill behavior (same as CustomerHomeView)

    private func toggleWelcomePill() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showWelcomePill.toggle()
        }
        autoHideTask?.cancel()
        if showWelcomePill {
            autoHideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    showWelcomePill = false
                }
            }
        } else {
            autoHideTask = nil
        }
    }
}

// MARK: - SwiftUI wrapper for EKEventEditViewController

private struct EventEditView: UIViewControllerRepresentable {
    let job: Job
    var onComplete: ((EKEventEditViewAction) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let vc = EKEventEditViewController()
        vc.eventStore = store

        let event = EKEvent(eventStore: store)
        event.title = "Job: \(job.title) — \(job.clientName)"
        event.startDate = job.scheduledStart
        event.endDate = job.scheduledStart.addingTimeInterval(job.estimatedHours * 3600)
        event.location = "\(job.address.line1), \(job.address.city) \(job.address.postcode)"
        event.notes = job.notes

        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let parent: EventEditView
        init(_ parent: EventEditView) { self.parent = parent }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
            parent.onComplete?(action)
        }
    }
}
