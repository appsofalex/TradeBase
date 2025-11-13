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

    // Logo pill state
    @State private var showWelcomePill = false
    @State private var autoHideTask: Task<Void, Never>? = nil

    // Target width for the expanded pill
    private let pillExpandedWidth: CGFloat = 220

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

                // Keep the bell on the right
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
                                Task { await NotificationsScheduler.shared.scheduleDraftReminder(for: updated) }
                            },
                            onPublish: { updated in
                                store.upsert(updated)
                                store.publish(id: updated.id)
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
                    .background(Capsule().fill(TBTheme.brand)) // pill
                    .foregroundStyle(.white)
            }
            .padding(.top, 6)
            .buttonStyle(.plain)

            Button {
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
                .background(Capsule().fill(.ultraThinMaterial)) // pill to match curvature
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.15))
                )
                .foregroundStyle(TBTheme.offWhite)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
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
        let owner = state.profile.id
        let draft = store.createDraft(for: owner, title: "")
        newDraftID = draft.id
        shouldNavigateToPostJob = true
    }

    // MARK: - Logo pill behavior

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
