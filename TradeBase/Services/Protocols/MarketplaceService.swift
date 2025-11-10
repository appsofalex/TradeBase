//
//  MarketplaceService.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

struct MarketFilter: Equatable {
    var radiusKm: Double = 25

    // Backward compatibility: keep single trade, but bridge to selectedTrades.
    // Prefer using selectedTrades going forward.
    var trade: TradeType? {
        get { selectedTrades.first }
        set {
            selectedTrades.removeAll()
            if let t = newValue { selectedTrades.insert(t) }
        }
    }

    // New: multi-select trades
    var selectedTrades: Set<TradeType> = []

    var minPay: Decimal? = nil
    var instantBookOnly: Bool = false
    var verifiedOnly: Bool = false
}

protocol MarketplaceService {
    func searchLeads(filter: MarketFilter) async throws -> [MarketplaceLead]
}

