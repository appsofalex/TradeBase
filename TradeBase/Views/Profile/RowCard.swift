import SwiftUI

struct RowCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TBTheme.brand.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(TBTheme.brand)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(TBTheme.offWhite)
                    Text(subtitle)
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
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

#Preview {
    ZStack {
        TBTheme.gradient.ignoresSafeArea()
        VStack(spacing: 16) {
            RowCard(
                title: "Reviews",
                subtitle: "See all your reviews from tradespeople.",
                icon: "star.leadinghalf.filled",
                action: {}
            )
            .padding(.horizontal, 18)
        }
    }
}
