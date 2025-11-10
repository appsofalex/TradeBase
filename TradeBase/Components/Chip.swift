//
//  Chip.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct Chip: View, Identifiable {
    let id = UUID()
    var text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12).fill(TBTheme.brand.opacity(0.12)))
    }
}
