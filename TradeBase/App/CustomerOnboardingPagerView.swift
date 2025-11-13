//
//  CustomerOnboardingPagerView.swift
//  TradeBase
//

import SwiftUI

struct CustomerOnboardingPagerView: View {
    @Environment(AppState.self) private var state
    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let symbolName: String
        let cta: String
    }

    // Customer-focused pages, same visual rhythm as tradesperson pager
    private let pages: [Page] = [
        .init(
            title: "Post a job in minutes",
            subtitle: "Describe your job and preferred time. It’s free to post.",
            symbolName: "square.and.pencil.circle.fill",
            cta: "Continue"
        ),
        .init(
            title: "Get quotes from local tradespeople",
            subtitle: "Rated tradespeople nearby will respond with quotes.",
            symbolName: "person.3.sequence.fill",
            cta: "Continue"
        ),
        .init(
            title: "Book with confidence",
            subtitle: "Read reviews, chat securely, and confirm the booking.",
            symbolName: "checkmark.seal.fill",
            cta: "Get started"
        )
    ]

    // Match layout constants from OnboardingPagerView for consistent alignment
    private let iconAreaHeight: CGFloat = 120
    private let titleAreaHeight: CGFloat = 64
    private let subtitleAreaHeight: CGFloat = 88
    private let iconBaseSize: CGFloat = 84

    var body: some View {
        ZStack {
            TBTheme.gradient.ignoresSafeArea()
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, p in
                        VStack(spacing: 12) {
                            Spacer(minLength: 28)

                            ZStack {
                                Image(systemName: p.symbolName)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(TBTheme.offWhite)
                                    .font(.system(size: iconBaseSize, weight: .semibold))
                            }
                            .frame(height: iconAreaHeight)

                            ZStack {
                                Text(p.title)
                                    .multilineTextAlignment(.center)
                                    .font(.title2.bold())
                                    .foregroundStyle(TBTheme.offWhite)
                                    .padding(.horizontal)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                            }
                            .frame(height: titleAreaHeight)

                            ZStack {
                                Text(p.subtitle)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                                    .padding(.horizontal)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.9)
                            }
                            .frame(height: subtitleAreaHeight)

                            Spacer()

                            PillButton(title: p.cta, style: .light) {
                                if page < pages.count - 1 {
                                    withAnimation(.easeInOut) { page += 1 }
                                } else {
                                    state.navigationDirection = .forward
                                    state.customerOnboardingCompleted = true
                                }
                            }
                            .padding(.horizontal, 24)

                            Spacer(minLength: 16)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        // Native back chevron in the nav bar (no custom overlay)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        state.selectedRole = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
            }
        }
    }
}
