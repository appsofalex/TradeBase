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
                                Text("TradeBase Premium")
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
                                           subtitle: "Boost listings so more local pros see them.")
                                benefitRow(icon: "bolt.fill",
                                           title: "Faster responses",
                                           subtitle: "Instant alerts to tradespeople for quicker replies.")
                                benefitRow(icon: "checkmark.seal.fill",
                                           title: "Verified pros first",
                                           subtitle: "Matches prioritise top-rated, verified pros.")
                                benefitRow(icon: "heart.text.square.fill",
                                           title: "Shortlist & sync",
                                           subtitle: "Save favourites and access them anywhere.")
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

    private func upgrade() {
        state.profile.isPremium = true
        state.saveProfile()
        dismiss()
    }
}
