//
//  CustomerTabView.swift
//  TradeBase
//

import SwiftUI

struct CustomerTabView: View {
    @Environment(\.appState) private var state
    @State private var selectedTab: Tab = .home

    // Changing this ID forces the Profile tab view (and its NavigationStack) to recreate.
    @State private var profileViewID = UUID()

    enum Tab: Hashable {
        case home, myJobs, community, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CustomerHomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

            MyJobsView()
                .tabItem { Label("My Jobs", systemImage: "doc.text.magnifyingglass") }
                .tag(Tab.myJobs)

            CommunitiesView()
                .tabItem { Label("Community", systemImage: "person.3") }
                .tag(Tab.community)

            // Give Profile a resettable identity so it pops to root when returning.
            ProfileView()
                .id(profileViewID)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(TBTheme.brand)
        .background(TBTheme.gradient.ignoresSafeArea())
        .onChange(of: selectedTab) { newValue, _ in
            if newValue == .profile {
                profileViewID = UUID()
            }
        }
        .onChange(of: state.pendingJobResumeID) { newValue, _ in
            if newValue != nil {
                selectedTab = .myJobs
            }
        }
        .onChange(of: state.navigateToMyJobsSignal) { _, _ in
            selectedTab = .myJobs
        }
        .task {
            if state.pendingJobResumeID != nil {
                selectedTab = .myJobs
            }
        }
    }
}
