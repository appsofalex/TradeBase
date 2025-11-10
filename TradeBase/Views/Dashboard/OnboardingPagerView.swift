//
//  OnboardingPagerView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct OnboardingPagerView: View {
    @Environment(AppState.self) private var state
    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let symbolName: String
        let cta: String
    }

    private let pages: [Page] = [
        .init(
            title: "Fill your calendar with quality work",
            subtitle: "Find verified leads that match your trade and location — spend less time chasing, and more time earning.",
            symbolName: "calendar.circle.fill",
            cta: "Continue"
        ),
        .init(
            title: "Quote faster, win more jobs",
            subtitle: "Smart lead details and tools help you reply quickly and professionally.",
            symbolName: "hammer.fill",
            cta: "Continue"
        ),
        .init(
            title: "Keep customers in the loop",
            subtitle: "Simple scheduling and updates keep every job on track and stress‑free.",
            symbolName: "message.fill",
            cta: "Get started"
        )
    ]

    // Layout constants to enforce consistent alignment across pages
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
                                    .scaleEffect(p.symbolName == "calendar.circle.fill" ? 1.12 : 1.0)
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
                                    state.tradespersonOnboardingCompleted = true
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
                        // Go back to role picker instead of switching to customer.
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

// The previous placeholder image extension is no longer needed for SF Symbols.
// Keeping it here does no harm, but it will be unused now.
private extension Image {
    init(_ name: String) {
        if UIImage(named: name) != nil {
            self.init(name, bundle: nil)
        } else {
            self = Image(systemName: "wrench.and.screwdriver")
        }
    }
}

