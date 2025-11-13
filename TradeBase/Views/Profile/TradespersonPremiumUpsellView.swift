// PremiumUpsellView.swift
import SwiftUI

struct PremiumUpsellView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                // Static (non-scrolling) layout
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "bolt.badge.a")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(TBTheme.brand)
                        Text("TradeBase Pro")
                            .font(.title2.bold())
                            .foregroundStyle(TBTheme.offWhite)
                        Text("Get more jobs, stand out, and save time.")
                            .foregroundStyle(TBTheme.offWhiteSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Benefits
                    VStack(alignment: .leading, spacing: 14) {
                        benefitRow(icon: "location.circle.fill", title: "Location filter", subtitle: "Find local jobs fast.")
                        benefitRow(icon: "checkmark.seal.fill", title: "Verified badge", subtitle: "Boost customer trust.")
                        benefitRow(icon: "bolt.fill", title: "Instant booking", subtitle: "Let customers book you instantly.")
                        benefitRow(icon: "message.fill", title: "Message notifications", subtitle: "Get alerts when you receive a message.")
                        benefitRow(icon: "dollarsign.circle.fill", title: "Income tracker", subtitle: "See how much you've earnt over time.")
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                    // Price + CTA
                    VStack(spacing: 10) {
                        Text("£6.99/month")
                            .font(.title3.bold())
                            .foregroundStyle(TBTheme.offWhite)
                        Text("Cancel anytime • No hidden fees")
                            .font(.footnote)
                            .foregroundStyle(TBTheme.offWhiteSecondary)

                        // Non-interactive pill: Premium coming soon (branded) — use Capsule to match Dismiss curvature
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Premium coming soon…")
                                .fontWeight(.semibold)
                        }
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14) // keep current height
                        .background(Capsule().fill(TBTheme.brand))
                        .padding(.top, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Premium coming soon")

                        // Big bottom button: Dismiss (closes the upsell)
                        Button {
                            dismiss()
                        } label: {
                            Text("Dismiss")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(TBTheme.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 2)
                    }
                }
                .padding(20)
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
        .presentationBackground(.clear)
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
}
