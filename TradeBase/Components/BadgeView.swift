//
//  BadgeView.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct BadgeView: View {
    var text: String
    var icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TBTheme.brand.opacity(0.12), in: Capsule())
            .foregroundStyle(TBTheme.brand)
    }
}
