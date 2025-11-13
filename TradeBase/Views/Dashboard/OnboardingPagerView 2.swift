//
//  OnboardingPagerView 2.swift
//  TradeBase
//
//  Legacy/experimental onboarding pager kept for reference.
//  Renamed to avoid clashing with the production OnboardingPagerView.
//

import SwiftUI

struct OnboardingPagerLegacyView: View {
    @Environment(AppState.self) private var state
    @State private var page = 0

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    onboardingPage(
                        title: "Welcome",
                        subtitle: "TradeBase helps tradespeople and customers connect.",
                        icon: "handshake.fill"
                    ).tag(0)

                    onboardingPage(
                        title: "Community",
                        subtitle: "Ask questions, share tips, and learn together.",
                        icon: "person.3.fill"
                    ).tag(1)

                    onboardingPage(
                        title: "Get started",
                        subtitle: "Sign in to unlock all features.",
                        icon: "bolt.fill"
                    ).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxHeight: 420)

                PillButton(title: page == 2 ? "Continue" : "Next", style: .light) {
                    if page < 2 { withAnimation { page += 1 } }
                    else {
                        // Mirror production behavior and set the appropriate onboarding flag.
                        state.navigationDirection = .forward
                        switch state.selectedRole {
                        case .tradesperson:
                            state.tradespersonOnboardingCompleted = true
                        case .customer:
                            state.customerOnboardingCompleted = true
                        case .none:
                            break
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    private func onboardingPage(title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(TBTheme.brand)
            Text(title)
                .font(.title.bold())
                .foregroundStyle(TBTheme.offWhite)
            Text(subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(TBTheme.offWhiteSecondary)
                .padding(.horizontal, 24)
        }
    }
}
