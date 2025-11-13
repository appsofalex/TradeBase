import SwiftUI

struct CustomerPremiumUpsellView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                TBTheme.gradient.ignoresSafeArea()

                GeometryReader { proxy in
                    // Center the content vertically within available height
                    VStack {
                        Spacer(minLength: 0)

                        VStack(spacing: 20) {
                            // Header
                            VStack(spacing: 6) {
                                Image(systemName: "bolt.badge.a")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(TBTheme.brand)
                                Text("TradeBase Pro")
                                    .font(.title2.bold())
                                    .foregroundStyle(TBTheme.offWhite)
                                Text("Post smarter, hear back faster, and hire with confidence.")
                                    .foregroundStyle(TBTheme.offWhiteSecondary)
                                    .multilineTextAlignment(.center)
                            }

                            // Customer-focused benefits
                            VStack(alignment: .leading, spacing: 14) {
                                benefitRow(icon: "arrow.up.circle.fill",
                                           title: "Featured job posts",
                                           subtitle: "Reach more tradespeople with your job listings.")
                                benefitRow(icon: "info.circle.fill",
                                           title: "Job insights",
                                           subtitle: "See who has viewed your job.")
                                benefitRow(icon: "checkmark.seal.fill",
                                           title: "Verified pros first",
                                           subtitle: "Get seen by more verified tradespeople.")
                                benefitRow(icon: "message.fill",
                                           title: "Message notifications",
                                           subtitle: "Get alerts when you receive a message.")
                                benefitRow(icon: "eye.fill",
                                           title: "Read receipts",
                                           subtitle: "See when your messages are viewed.")
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )

                            // Price + CTA
                            VStack(spacing: 10) {
                                Text("£2.99/month")
                                    .font(.title3.bold())
                                    .foregroundStyle(TBTheme.offWhite)
                                Text("Cancel anytime • No hidden fees")
                                    .font(.footnote)
                                    .foregroundStyle(TBTheme.offWhiteSecondary)

                                // Branded pill — match “Post a job”
                                HStack(spacing: 8) {
                                    Image(systemName: "star.fill")
                                    Text("Pro coming soon…")
                                        .fontWeight(.bold)
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(Capsule().fill(TBTheme.brand))
                                .padding(.top, 4)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Pro coming soon")

                                // Secondary pill — Dismiss
                                Button {
                                    dismiss()
                                } label: {
                                    Text("Dismiss")
                                        .font(.headline)
                                        .foregroundStyle(TBTheme.offWhite)
                                        .padding(.vertical, 14)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            Capsule()
                                                .fill(.ultraThinMaterial)
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 20)

                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
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
        .presentationBackground(.clear)
    }

    @ViewBuilder
    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(TBTheme.brand)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TBTheme.offWhite)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TBTheme.offWhiteSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
