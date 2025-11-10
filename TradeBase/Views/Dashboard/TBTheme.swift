//
//  TBTheme-Dashboard.swift
//  TradeBase
//
//  Created by Scaffolding.
//

import SwiftUI

// Experimental/alternate palette kept under a distinct namespace to avoid clashes with TBTheme.
enum DashboardTheme {
    static let brand = Color(hue: 0.08, saturation: 0.85, brightness: 0.95) // warm amber/orange
    static let brandSecondary = Color(hue: 0.58, saturation: 0.60, brightness: 0.85) // teal accent

    static let offWhite = Color.white.opacity(0.95)
    static let offWhiteSecondary = Color.white.opacity(0.7)

    static let title = Color.white
    static let subtext = Color.white.opacity(0.7)

    static let gradient = LinearGradient(
        colors: [
            Color.black,
            Color(hue: 0.62, saturation: 0.32, brightness: 0.22),
            Color(hue: 0.62, saturation: 0.26, brightness: 0.16)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
