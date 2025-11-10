//
//  Stars.swift
//  TradeBase
//

import SwiftUI

struct Stars: View {
    var rating: Int
    var max: Int = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max, id: \.self) { idx in
                Image(systemName: idx < rating ? "star.fill" : "star")
                    .foregroundStyle(idx < rating ? .yellow : .gray)
            }
        }
    }
}

