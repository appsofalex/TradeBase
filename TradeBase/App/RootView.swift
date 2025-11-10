//
//  RootView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    fileprivate enum Tab: Hashable {
        case jobs, leads, community, profile
    }
    @State private var selectedTab: Tab = .jobs
    @State private var profileViewID = UUID()

    private var shouldShowTradespersonSetup: Bool {
        state.isAuthenticated &&
        state.selectedRole == .tradesperson &&
        state.needsSetup(for: .tradesperson)
    }

    private var shouldShowCustomerSetup: Bool {
        state.isAuthenticated &&
        state.selectedRole == .customer &&
        state.needsSetup(for: .customer) &&
        state.pendingJobResumeID == nil &&
        state.bypassCustomerSetupOnce == false
    }

    private var directionalTransition: AnyTransition {
        switch state.navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .back:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }

    var body: some View {
        RootContent(
            selectedTab: $selectedTab,
            profileViewID: $profileViewID,
            shouldShowTradespersonSetup: shouldShowTradespersonSetup,
            shouldShowCustomerSetup: shouldShowCustomerSetup,
            directionalTransition: directionalTransition
        )
        .applyRootModifiers(
            state: state,
            selectedTab: $selectedTab,
            profileViewID: $profileViewID
        )
        .task {
            if state.isAuthenticated {
                await state.load()
                await state.refreshUnreadCount()
                if state.selectedRole == .tradesperson {
                    selectedTab = .jobs
                }
                state.startMessagingListeners()
            }
        }
    }
}

// MARK: - Extracted content view to reduce type-checking complexity

private struct RootContent: View {
    @Environment(AppState.self) private var state

    @Binding var selectedTab: RootView.Tab
    @Binding var profileViewID: UUID

    let shouldShowTradespersonSetup: Bool
    let shouldShowCustomerSetup: Bool
    let directionalTransition: AnyTransition

    var body: some View {
        ZStack {
            backgroundView
            mainContent
        }
    }

    // Isolate the gradient; wrapping in AnyView stabilizes ZStack’s type
    private var backgroundView: some View {
        AnyView(
            TBTheme.gradient
                .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        if state.selectedRole == nil {
            RolePickerView()
                .transition(directionalTransition)
        } else if state.isAuthenticated {
            authenticatedContent
        } else {
            NavigationStack {
                unauthenticatedContent
                    .navigationBarTitleDisplayMode(.inline)
            }
            .transition(directionalTransition)
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if state.selectedRole == .tradesperson {
            tradespersonContent
        } else if state.selectedRole == .customer {
            customerContent
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var tradespersonContent: some View {
        if shouldShowTradespersonSetup {
            NavigationStack {
                TradespersonSetupFlow()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .transition(directionalTransition)
        } else {
            tradespersonTabView
                .transition(directionalTransition)
        }
    }

    @ViewBuilder
    private var customerContent: some View {
        if shouldShowCustomerSetup {
            NavigationStack {
                CustomerSetupFlow()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .transition(directionalTransition)
        } else {
            CustomerTabView()
                .transition(directionalTransition)
        }
    }

    @ViewBuilder
    private var unauthenticatedContent: some View {
        if state.selectedRole == .customer {
            if state.customerOnboardingCompleted == false {
                CustomerOnboardingPagerView()
            } else {
                AuthEntryView()
            }
        } else {
            if state.tradespersonOnboardingCompleted == false {
                OnboardingPagerView()
            } else {
                AuthEntryView()
            }
        }
    }

    private var tradespersonTabView: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Jobs", systemImage: "calendar.badge.clock") }
                .tag(RootView.Tab.jobs)

            LeadsView()
                .tabItem { Label("Leads", systemImage: "list.bullet.rectangle.portrait") }
                .tag(RootView.Tab.leads)

            CommunitiesView()
                .tabItem { Label("Community", systemImage: "person.3") }
                .tag(RootView.Tab.community)

            ProfileView()
                .id(profileViewID)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(RootView.Tab.profile)
        }
        .tint(TBTheme.brand)
    }
}

// MARK: - View modifier bundling reactive chains

private extension View {
    func applyRootModifiers(
        state: AppState,
        selectedTab: Binding<RootView.Tab>,
        profileViewID: Binding<UUID>
    ) -> some View {
        self
            .onChange(of: state.isAuthenticated) { isAuth, _ in
                if isAuth {
                    Task {
                        await state.load()
                        await state.refreshUnreadCount()
                    }
                    if state.selectedRole == .tradesperson {
                        selectedTab.wrappedValue = .jobs
                    }
                    state.startMessagingListeners()
                } else {
                    state.stopMessagingListeners()
                }
            }
            .onChange(of: selectedTab.wrappedValue) { newValue, _ in
                if newValue == .profile {
                    profileViewID.wrappedValue = UUID()
                }
            }
            .onChange(of: state.selectedRole) { newRole, oldRole in
                if oldRole == nil, newRole != nil {
                    state.navigationDirection = .forward
                } else if oldRole != nil, newRole == nil {
                    state.navigationDirection = .back
                }
                if newRole == .tradesperson {
                    selectedTab.wrappedValue = .jobs
                }
                Task { await state.refreshUnreadCount() }
                state.startMessagingListeners()
            }
            .onChange(of: state.tradespersonOnboardingCompleted) { newValue, oldValue in
                if oldValue == false, newValue == true {
                    state.navigationDirection = .forward
                } else if oldValue == true, newValue == false {
                    state.navigationDirection = .back
                }
            }
            .onChange(of: state.customerOnboardingCompleted) { newValue, oldValue in
                if oldValue == false, newValue == true {
                    state.navigationDirection = .forward
                } else if oldValue == true, newValue == false {
                    state.navigationDirection = .back
                }
            }
            .onChange(of: state.tradespersonSetupCompleted) { newValue, _ in
                if newValue && state.selectedRole == .tradesperson {
                    selectedTab.wrappedValue = .jobs
                }
            }
            .animation(.easeInOut(duration: 0.28), value: state.selectedRole)
            .animation(.easeInOut(duration: 0.28), value: state.isAuthenticated)
            .animation(.easeInOut(duration: 0.28), value: state.tradespersonOnboardingCompleted)
            .animation(.easeInOut(duration: 0.28), value: state.customerOnboardingCompleted)
            .animation(.easeInOut(duration: 0.28), value: state.navigationDirection)
    }
}
