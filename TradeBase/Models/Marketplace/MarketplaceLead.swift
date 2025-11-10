//
//  MarketplaceLead.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

struct MarketplaceLead: Identifiable, Hashable {
    var id: UUID
    var title: String
    var category: TradeType?
    var description: String
    var location: Address

    var budgetType: JobBudgetType
    var budgetMin: Decimal?
    var budgetMax: Decimal?
    var currency: String

    var startDate: Date?
    var isUrgent: Bool

    var photoURLs: [URL]

    var createdAt: Date
    var updatedAt: Date

    // New: identity of the customer who posted this lead (provider-scoped)
    // e.g. "email:john@doe.com" or "google:abc123"
    var posterIdentity: String? = nil

    // Optional app-level UUID for the poster (if available)
    var posterAppID: UUID? = nil
}

