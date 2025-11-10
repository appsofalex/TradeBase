import SwiftUI

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let icon: String?

    init(title: String, subtitle: String, icon: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 52, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(TBTheme.brand)
                    .padding(.bottom, 4)
            }

            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(TBTheme.title)

            Text(subtitle)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(TBTheme.subtext)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
