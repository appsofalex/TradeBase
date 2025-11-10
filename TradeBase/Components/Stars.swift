//
//  Stars.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct Stars: View {
    var rating: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < rating ? "star.fill" : "star").imageScale(.small)
            }
        }
        .foregroundStyle(.yellow)
    }
}
