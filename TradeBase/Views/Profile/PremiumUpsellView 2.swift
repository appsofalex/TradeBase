// PremiumUpsellView.swift
import SwiftUI

// Renamed to avoid conflicting with the canonical PremiumUpsellView.
// This variant can be used for previews or experimentation.
struct PremiumUpsellScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 6) {
                            Image(systemName: "bolt.badge.a")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(TBTheme.brand)
                            Text("TradeBase Premium")
                                .font(.title2.bold())
                                .foregroundStyle(TBTheme.offWhite)
                            Text("Get more jobs, stand out, and save time.")
                                .foregroundStyle(TBTheme.offWhiteSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)

                        // Benefits
                        VStack(alignment: .leading, spacing: 14) {
                            benefitRow(icon: "arrow.up.circle.fill", title: "Priority placement", subtitle: "Appear higher in local searches to win more leads.")
                            benefitRow(icon: "checkmark.seal.fill", title: "Verified badge", subtitle: "Build trust with a verification badge on your profile.")
                            benefitRow(icon: "bolt.fill", title: "Instant booking", subtitle: "Let customers book you instantly to reduce back-and-forth.")
                            benefitRow(icon: "megaphone.fill", title: "Boosted visibility", subtitle: "Get highlighted in Marketplace to stand out.")
                            benefitRow(icon: "headset.circle.fill", title: "Priority support", subtitle: "Faster help when you need it.")
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                        // Price + CTA
                        VStack(spacing: 10) {
                            Text("£9.99/month")
                                .font(.title3.bold())
                                .foregroundStyle(TBTheme.offWhite)
                            Text("Cancel anytime • No hidden fees")
                                .font(.footnote)
                                .foregroundStyle(TBTheme.offWhiteSecondary)

                            Button {
                                upgrade()
                            } label: {
                                HStack {
                                    Image(systemName: "star.fill")
                                    Text("Upgrade to Premium")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(TBTheme.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 4)

                            Button {
                                dismiss()
                            } label: {
                                Text("Maybe later")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .tint(TBTheme.offWhite)
        }
    }

    @ViewBuilder
    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(TBTheme.brand)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TBTheme.offWhite)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TBTheme.offWhiteSecondary)
            }
            Spacer()
        }
    }

    private func upgrade() {
        // Placeholder for purchase flow; toggle Premium and persist for now.
        state.profile.isPremium = true
        state.saveProfile()
        dismiss()
    }
}
