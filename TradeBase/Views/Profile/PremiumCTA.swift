import SwiftUI

struct PremiumCTA: View {
    let isPremium: Bool
    var tap: () -> Void

    var body: some View {
        if isPremium {
            // Show current status as a non-interactive card
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("You’re on Premium")
                        .font(.headline)
                        .foregroundStyle(TBTheme.offWhite)
                    Text("Enjoy priority placement and more benefits.")
                        .font(.subheadline)
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You’re on Premium. Enjoy priority placement and more benefits.")
        } else {
            // Tappable upsell card
            Button(action: tap) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TBTheme.brand.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "bolt.badge.a")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(TBTheme.brand)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Explore Premium")
                            .font(.headline)
                            .foregroundStyle(TBTheme.offWhite)
                        Text("Stand out, get more jobs, and save time.")
                            .font(.subheadline)
                            .foregroundStyle(TBTheme.offWhiteSecondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(TBTheme.offWhiteSecondary)
                        .imageScale(.small)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Explore Premium. Stand out, get more jobs, and save time.")
        }
    }
}

#Preview {
    ZStack {
        TBTheme.gradient.ignoresSafeArea()
        VStack(spacing: 16) {
            PremiumCTA(isPremium: false, tap: {})
            PremiumCTA(isPremium: true, tap: {})
        }
        .padding(.horizontal, 18)
    }
}
