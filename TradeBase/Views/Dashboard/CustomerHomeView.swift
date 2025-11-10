//
//  CustomerHomeView.swift
//  TradeBase
//

import SwiftUI

struct CustomerHomeView: View {
    @Environment(\.appState) private var state
    @Environment(\.customerJobListingStore) private var store

    // Gate presentation state
    @State private var showAuthEntrySheet = false
    @State private var shouldNavigateToPostJob = false
    // New: the draft we’ll create and edit
    @State private var newDraftID: UUID? = nil

    // Phase 2: message hub
    @State private var showMessageHub = false

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    // Match Community/Profile: left-aligned bubbly header
                    Text("Home").tbLargeHeader()

                    // Center the CTA block vertically within remaining space
                    VStack {
                        Spacer()
                        ctaBlock
                            .padding(.horizontal, 20)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                                        .padding(.top, -2)      // match DashboardView placement
                                        .padding(.trailing, -4) // match DashboardView placement
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
            // Invisible navigation trigger that we flip on after successful auth
            .background(
                NavigationLink(isActive: $shouldNavigateToPostJob) {
                    if let id = newDraftID,
                       let draft = store.listings.first(where: { (item: JobListing) in item.id == id }) {
                        JobListingEditorSheet(
                            listing: draft,
                            showPublish: true,
                            onSave: { updated in
                                store.upsert(updated)
                                // For drafts, schedule a reminder to finish later
                                Task { await NotificationsScheduler.shared.scheduleDraftReminder(for: updated) }
                            },
                            onPublish: { updated in
                                // Persist local fields first
                                store.upsert(updated)
                                // Change status to active locally
                                store.publish(id: updated.id)

                                // Mirror to CloudKit (best-effort)
                                Task {
                                    let identity = state.currentAuthIdentity()
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

                                // On publish, schedule a start reminder (if date present)
                                Task {
                                    await state.requestNotificationPermissionsIfNeeded()
                                    await NotificationsScheduler.shared.scheduleStartReminder(for: updated)
                                }
                            },
                            viewTitle: "Post Job"
                        )
                        .environment(\.customerJobListingStore, store)
                        .environment(\.appState, state)
                    } else {
                        // Safety fallback if draft missing
                        Text("Preparing editor…")
                            .task { await prepareAndNavigateToDraft() }
                    }
                } label: { EmptyView() }
                .hidden()
            )
        }
        // Best-effort: fetch some community posts to populate the highlight
        .task {
            if state.posts.isEmpty {
                _ = await state.refreshCommunity(city: nil)
            }
        }
        // Best-effort: ensure unread count is up to date so the red dot appears promptly
        .task {
            await state.refreshUnreadCount()
        }
        // If auth state changes to an allowed provider while the sheet is up, auto-proceed.
        .onChange(of: state.authProvider) { _, _ in
            if state.canCustomerPostJobs && showAuthEntrySheet {
                showAuthEntrySheet = false
                // Defer navigation until the sheet fully dismisses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    Task { await prepareAndNavigateToDraft() }
                }
            }
        }
        // Present the gated sign-in sheet
        .sheet(isPresented: $showAuthEntrySheet, onDismiss: {
            if state.canCustomerPostJobs {
                Task { await prepareAndNavigateToDraft() }
            }
        }) {
            // Hide guest skip so only Apple/Google are offered for this gate.
            AuthEntryView(presentation: .gatedModal, hideGuestSkip: true)
        }
    }

    // MARK: - CTA

    private var ctaBlock: some View {
        VStack(spacing: 10) {
            Text("Ready to get started?")
                .font(.title2.bold())
                .foregroundStyle(TBTheme.offWhite)
            Text("Let's find you an epic tradesperson to get the job done.")
                .foregroundStyle(TBTheme.offWhiteSecondary)

            Button {
                // Gate: Only Apple/Google signed-in accounts can post jobs.
                if state.canCustomerPostJobs {
                    Task { await prepareAndNavigateToDraft() }
                } else {
                    showAuthEntrySheet = true
                }
            } label: {
                Text("Post a job")
                    .font(.headline)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14).fill(TBTheme.brand))
                    .foregroundStyle(.white)
            }
            .padding(.top, 6)
            .buttonStyle(.plain)

            // Secondary quick action to jump to My Jobs
            Button {
                // Coordinate navigation via AppState flags observed by MyJobsView
                state.preferredMyJobsStatus = .active
                state.navigateToMyJobsSignal += 1
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("View My Jobs")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15))
                )
                .foregroundStyle(TBTheme.offWhite)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420) // keep the block nicely centered on wider screens
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TBTheme.brand)
            Text(text)
                .foregroundStyle(TBTheme.title)
        }
    }

    // MARK: - Draft creation + navigation

    @MainActor
    private func prepareAndNavigateToDraft() async {
        // Create a new draft and navigate to the editor
        let owner = state.profile.id
        // IMPORTANT: seed with an empty title so the editor shows its placeholder.
        let draft = store.createDraft(for: owner, title: "")
        newDraftID = draft.id
        shouldNavigateToPostJob = true
    }
}
