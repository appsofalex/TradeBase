//
//  EmptyStateView.swift (dashboard variant)
//  TradeBase
//

import SwiftUI

struct DashboardEmptyStateView: View {
    var title: String
    var subtitle: String
    var icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(TBTheme.offWhiteSecondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TBTheme.offWhite)
            Text(subtitle)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(TBTheme.offWhiteSecondary)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
