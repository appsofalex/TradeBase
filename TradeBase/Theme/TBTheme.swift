//
//  TBTheme.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI

struct TBTheme {
    static let gradient = LinearGradient(
        colors: [
            Color(.sRGB, red: 0.09, green: 0.09, blue: 0.12, opacity: 1),
            Color(.sRGB, red: 0.13, green: 0.17, blue: 0.27, opacity: 1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brand = Color(red: 0.10, green: 0.64, blue: 0.56)
    static let brandMuted = Color(red: 0.08, green: 0.50, blue: 0.44)
    static let surface = Color(uiColor: .secondarySystemBackground)

    // Off-white palette for dark backgrounds (legacy)
    static let offWhite = Color(.sRGB, white: 0.92, opacity: 1.0)
    static let offWhiteSecondary = Color(.sRGB, white: 0.78, opacity: 1.0)

    // Centralized colors
    static let subtext = Color(.label)     // for small/secondary text, high contrast
    static let title   = Color(.label)     // for headings/titles, high contrast
}
