//
//  TradeType.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

enum TradeType: String, CaseIterable, Identifiable, Codable {
    case electrician, plumber, carpenter, roofer, painter, hvac, tiler, landscaper, generalBuilder, windowsAndDoors
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .generalBuilder:
            return "General Builder"
        case .hvac:
            return "HVAC"
        case .windowsAndDoors:
            return "Windows & doors"
        default:
            return rawValue.capitalized
        }
    }
}

