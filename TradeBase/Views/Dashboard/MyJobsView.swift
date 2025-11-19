//
//  MyJobsView.swift
//  TradeBase
//

import SwiftUI
import PhotosUI
import CoreLocation
import UIKit

struct MyJobsView: View {
    @Environment(\.customerJobListingStore) private var store
    @Environment(\.appState) private var state

    @State private var selected: JobListingStatus = .active
    @State private var editingListing: JobListing? = nil
    @State private var sortMode: SortMode = .recent
    // Gate presentation/navigation state for posting a new job
    @State private var showAuthEntrySheet = false
    @State private var shouldNavigateToPostJob = false
    // New: draft created for editor
    @State private var newDraftID: UUID? = nil

    // NEW: publish guard alert
    @State private var showPublishIdentityAlert = false

    private let allStatuses: [JobListingStatus] = [.draft, .active, .inProgress, .completed, .closed]

    enum SortMode: String, CaseIterable, Identifiable {
        case recent, city
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recent: return "Recent"
            case .city: return "City (A–Z)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
                // Remove nav bar title; keep toolbar items
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
                // Invisible navigation trigger to push the editor after auth succeeds
                .background(navigationTrigger.hidden())
        }
        .sheet(item: $editingListing) { listing in
            JobListingEditorSheet(
                listing: listing,
                showPublish: listing.status == .draft,
                onSave: { updated in
                    // Persist locally
                    store.upsert(updated)

                    // Mirror edits to CloudKit when the job is visible to tradespeople
                    if updated.status == .active {
                        guard let identity = state.currentAuthIdentity() else {
                            showPublishIdentityAlert = true
                            return
                        }
                        Task {
                            let posterAppID = state.profile.id
                            print("[Publish] onSave upsert start id=\(updated.id) status=\(updated.status.rawValue)")
                            do {
                                try await state.jobLeadService.upsert(
                                    from: updated,
                                    posterIdentity: identity,
                                    posterAppID: posterAppID,
                                    photoFileURLs: updated.photos
                                )
                                print("[Publish] onSave upsert success id=\(updated.id)")
                            } catch {
                                print("[Publish] onSave upsert failed id=\(updated.id) error=\(error)")
                            }
                        }
                    }

                    // Removed: draft reminder scheduling
                    editingListing = nil
                },
                onPublish: { updated in
                    // Persist local fields first
                    store.upsert(updated)
                    // Change status to active locally
                    store.publish(id: updated.id)

                    // Mirror the freshly published job to CloudKit for tradespeople
                    guard let identity = state.currentAuthIdentity() else {
                        showPublishIdentityAlert = true
                        return
                    }
                    Task {
                        let posterAppID = state.profile.id
                        var activeCopy = updated
                        activeCopy.status = .active
                        activeCopy.updatedAt = Date()
                        print("[Publish] onPublish upsert start id=\(activeCopy.id) status=\(activeCopy.status.rawValue)")
                        do {
                            try await state.jobLeadService.upsert(
                                from: activeCopy,
                                posterIdentity: identity,
                                posterAppID: posterAppID,
                                photoFileURLs: activeCopy.photos
                            )
                            print("[Publish] onPublish upsert success id=\(activeCopy.id)")
                            // Optional: ensure background subscription exists on this device
                            try? await state.ensureLeadsSubscription()
                        } catch {
                            print("[Publish] onPublish upsert failed id=\(activeCopy.id) error=\(error)")
                        }
                    }

                    // Removed: permission request + start reminder scheduling
                    editingListing = nil
                }
            )
        }
        // Auto-proceed into the editor if auth provider changes to an allowed one while sheet is up
        .onChange(of: state.authProvider) { _, _ in
            if state.canCustomerPostJobs && showAuthEntrySheet {
                showAuthEntrySheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    Task { await prepareAndNavigateToDraft() }
                }
            }
        }
        // Present the gated sign-in sheet (Apple/Google only)
        .sheet(isPresented: $showAuthEntrySheet, onDismiss: {
            if state.canCustomerPostJobs {
                Task { await prepareAndNavigateToDraft() }
            }
        }) {
            AuthEntryView(presentation: .gatedModal, hideGuestSkip: true)
        }
        .onChange(of: state.pendingJobResumeID) { newValue, _ in
            if let id = newValue {
                presentEditor(for: id)
            }
        }
        .onChange(of: state.navigateToMyJobsSignal) { _, _ in
            if let preferred = state.preferredMyJobsStatus {
                selected = preferred
                state.preferredMyJobsStatus = nil
            }
        }
        .task {
            if let id = state.pendingJobResumeID {
                presentEditor(for: id)
            }
            // Apply any pending preferred section on first load
            if let preferred = state.preferredMyJobsStatus {
                selected = preferred
                state.preferredMyJobsStatus = nil
            }
        }
        // NEW: alert when trying to publish without an identity
        .alert("Sign in required", isPresented: $showPublishIdentityAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please sign in with Apple or Google before posting jobs so customers can be messaged.")
        }
    }

    // MARK: - Split out content to ease type-checking

    private var mainContent: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header matching Community/Profile (left-aligned with standard inset)
                Text("My Jobs").tbLargeHeader()

                VStack {
                    statusPicker
                    jobsSection
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Post a job (gated: Apple/Google only)
            Button {
                if state.canCustomerPostJobs {
                    Task { await prepareAndNavigateToDraft() }
                } else {
                    showAuthEntrySheet = true
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Post a job")

            // Existing Sort control
            Menu {
                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    private var navigationTrigger: some View {
        NavigationLink(isActive: $shouldNavigateToPostJob) {
            if let id = newDraftID,
               let draft = store.listings.first(where: { (item: JobListing) in item.id == id }) {
                // Replace missing EditorLauncher with the same editor you already use in this file.
                JobListingEditorSheet(
                    listing: draft,
                    showPublish: true,
                    onSave: { updated in
                        store.upsert(updated)
                        // Removed: draft reminder scheduling
                    },
                    onPublish: { updated in
                        store.upsert(updated)
                        store.publish(id: updated.id)
                        guard let identity = state.currentAuthIdentity() else {
                            showPublishIdentityAlert = true
                            return
                        }
                        Task {
                            let posterAppID = state.profile.id
                            var activeCopy = updated
                            activeCopy.status = .active
                            activeCopy.updatedAt = Date()
                            do {
                                try await state.jobLeadService.upsert(
                                    from: activeCopy,
                                    posterIdentity: identity,
                                    posterAppID: posterAppID,
                                    photoFileURLs: activeCopy.photos
                                )
                                try? await state.ensureLeadsSubscription()
                            } catch {
                                // best-effort
                            }
                        }
                        // Removed: permission request + start reminder scheduling
                    },
                    viewTitle: "Post Job"
                )
                .environment(\.customerJobListingStore, store)
                .environment(\.appState, state)
            } else {
                Text("Preparing editor…")
                    .task { await prepareAndNavigateToDraft() }
            }
        } label: { EmptyView() }
    }

    // MARK: - Subviews

    private var statusPicker: some View {
        Picker("Status", selection: $selected) {
            ForEach(allStatuses) { s in
                Text(displayName(for: s))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var jobsSection: some View {
        // Compute data in typed steps (helps the type-checker)
        let ownerId: UUID = state.profile.id
        let base: [JobListing] = store.byStatus(selected, ownerId: ownerId)
        let jobs: [JobListing] = sortMode == .recent ? base : base.sorted(by: MyJobsView.cityAscending)

        content(for: jobs)
    }

    @ViewBuilder
    private func content(for jobs: [JobListing]) -> some View {
        if jobs.isEmpty {
            Spacer()
            let empty = emptyState(for: selected)
            if #available(iOS 17.0, *) {
                ContentUnavailableView(empty.title,
                                       systemImage: "doc.plaintext",
                                       description: Text(empty.subtitle))
            } else {
                InlineEmptyState(title: empty.title,
                                 subtitle: empty.subtitle,
                                 icon: "doc.plaintext")
            }
            Spacer()
        } else {
            List {
                ForEach(jobs) { job in
                    RowWithAnchoredMenu(
                        job: job,
                        onChangeStatus: { newStatus in
                            updateStatus(job: job, to: newStatus)
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: selected == .active || selected == .closed) {
                        swipeButtons(for: job)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Row with anchored Menu

    private struct RowWithAnchoredMenu: View {
        let job: JobListing
        let onChangeStatus: (JobListingStatus) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(job.title)
                        .font(.headline)
                    Spacer()

                    // Status pill becomes the anchor for the dropdown
                    Menu {
                        // Drafts
                        Button {
                            onChangeStatus(.draft)
                        } label: {
                            Label("Drafts", systemImage: job.status == .draft ? "checkmark" : "circle")
                        }
                        .disabled(job.status == .draft)

                        // Posted
                        Button {
                            onChangeStatus(.active)
                        } label: {
                            Label("Posted", systemImage: job.status == .active ? "checkmark" : "circle")
                        }
                        .disabled(job.status == .active)

                        // Current
                        Button {
                            onChangeStatus(.inProgress)
                        } label: {
                            Label("Current", systemImage: job.status == .inProgress ? "checkmark" : "circle")
                        }
                        .disabled(job.status == .inProgress)

                        // Done
                        Button {
                            onChangeStatus(.completed)
                        } label: {
                            Label("Done", systemImage: job.status == .completed ? "checkmark" : "circle")
                        }
                        .disabled(job.status == .completed)
                    } label: {
                        HStack(spacing: 6) {
                            Text(displayName(for: job.status))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TBTheme.brand)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(TBTheme.brand)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.white.opacity(0.15))
                        )
                    }
                    .menuStyle(.automatic)
                    .accessibilityLabel("Change status")
                }

                HStack(spacing: 6) {
                    if let cat = job.category { Text(cat.displayName) }
                    if !job.location.city.isEmpty { Text("• \(job.location.city)") }
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
            .contentShape(Rectangle())
        }

        private func displayName(for status: JobListingStatus) -> String {
            switch status {
            case .draft: return "Drafts"
            case .active: return "Posted"
            case .inProgress: return "Current"
            case .completed: return "Done"
            case .closed: return "Closed"
            }
        }
    }

    // MARK: - Status update

    private func updateStatus(job: JobListing, to newStatus: JobListingStatus) {
        guard job.status != newStatus else { return }
        withAnimation(.easeInOut) {
            switch newStatus {
            case .draft:
                store.markDraft(id: job.id)
            case .active:
                store.publish(id: job.id)
            case .inProgress:
                store.markInProgress(id: job.id)
            case .completed:
                store.markCompleted(id: job.id)
            case .closed:
                store.close(id: job.id)
            }
        }

        // Mirror to CloudKit (best-effort) for statuses visible to tradespeople.
        // Skip mirroring for Drafts (not publicly visible).
        if newStatus != .draft {
            Task {
                do {
                    print("[Publish] updateStatus -> \(newStatus.rawValue) id=\(job.id)")
                    try await state.jobLeadService.updateStatus(recordName: job.id.uuidString, to: newStatus)
                    print("[Publish] updateStatus \(newStatus.rawValue) OK id=\(job.id)")
                } catch {
                    print("[Publish] updateStatus \(newStatus.rawValue) failed id=\(job.id) error=\(error)")
                }
            }
        }
    }

    // MARK: - Swipe Buttons

    @ViewBuilder
    private func swipeButtons(for job: JobListing) -> some View {
        switch selected {
        case .draft:
            Button(role: .destructive) {
                store.delete(id: job.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                editingListing = job
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(TBTheme.brand)

        case .active:
            Button(role: .destructive) {
                store.close(id: job.id)
                // Mirror to CloudKit (best-effort)
                Task {
                    do {
                        print("[Publish] updateStatus -> closed id=\(job.id)")
                        try await state.jobLeadService.updateStatus(recordName: job.id.uuidString, to: .closed)
                        print("[Publish] updateStatus closed OK id=\(job.id)")
                    } catch {
                        print("[Publish] updateStatus closed failed id=\(job.id) error=\(error)")
                    }
                }
            } label: {
                Label("Close", systemImage: "xmark")
            }
            .tint(.red)

            Button {
                editingListing = job
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(TBTheme.brand)

        case .closed:
            // Re-open first, Delete second
            Button {
                store.publish(id: job.id)
                // Mirror to CloudKit (best-effort)
                Task {
                    do {
                        print("[Publish] updateStatus -> active id=\(job.id)")
                        try await state.jobLeadService.updateStatus(recordName: job.id.uuidString, to: .active)
                        print("[Publish] updateStatus active OK id=\(job.id)")
                    } catch {
                        print("[Publish] updateStatus active failed id=\(job.id) error=\(error)")
                    }
                }
            } label: {
                Label("Re-open", systemImage: "arrow.uturn.left")
            }
            .tint(TBTheme.brand)

            Button(role: .destructive) {
                store.delete(id: job.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

        case .inProgress, .completed:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private static func cityAscending(_ lhs: JobListing, _ rhs: JobListing) -> Bool {
        lhs.location.city.localizedCaseInsensitiveCompare(rhs.location.city) == .orderedAscending
    }

    private func displayName(for status: JobListingStatus) -> String {
        switch status {
        case .draft: return "Drafts"
        case .active: return "Posted"
        case .inProgress: return "Current"
        case .completed: return "Done"
        case .closed: return "Closed"
        }
    }

    private func emptyState(for status: JobListingStatus) -> (title: String, subtitle: String) {
        switch status {
        case .draft:
            return ("No drafts yet", "Start a new job draft with the + button.")
        case .active:
            return ("No posted jobs", "Publish a job to make it visible to tradespeople.")
        case .inProgress:
            return ("No current jobs", "Jobs in progress will show here.")
        case .completed:
            return ("No completed jobs", "Finish jobs to see them here.")
        case .closed:
            return ("No closed jobs", "Closed jobs will be archived here.")
        }
    }

    private func presentEditor(for id: UUID) {
        if let listing = store.listings.first(where: { (item: JobListing) in item.id == id }) {
            editingListing = listing
            // Clear the pending flag so it doesn’t re-open
            state.pendingJobResumeID = nil
        }
    }

    // MARK: - Draft creation + navigation

    @MainActor
    private func prepareAndNavigateToDraft() async {
        let owner = state.profile.id
        // Seed with an empty title so the editor shows its placeholder.
        let draft = store.createDraft(for: owner, title: "")
        newDraftID = draft.id
        shouldNavigateToPostJob = true
    }
}

// MARK: - InlineEmptyState (iOS 16 fallback for ContentUnavailableView)

private struct InlineEmptyState: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(TBTheme.subtext)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(TBTheme.title)
            Text(subtitle)
                .foregroundStyle(TBTheme.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}
