//
//  SectionCard.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct SectionCard<Content: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundStyle(TBTheme.subtext)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TBTheme.title)
            }

            content()
                .foregroundStyle(TBTheme.title) // default content color; subviews can override
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading) // Ensure full available width
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(radius: 1)
    }
}
