//
//  MarketplaceLead.swift
//  TradeBase
//
//  Canonical model for job leads fetched from CloudKit (Public DB, JobLead records).
//  This struct is a pure data model. All CloudKit I/O is implemented in CloudKitJobLeadService.
//

import Foundation

struct MarketplaceLead: Identifiable, Hashable, Codable {
    // Core identifiers
    var id: UUID

    // Content
    var title: String
    var category: TradeType?
    var description: String

    // Location
    var location: Address

    // Budget
    var budgetType: JobBudgetType
    var budgetMin: Decimal?
    var budgetMax: Decimal?
    var currency: String

    // Timing
    var startDate: Date?
    var isUrgent: Bool

    // Media
    var photoURLs: [URL]

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Poster metadata (optional)
    var posterIdentity: String?
    var posterAppID: UUID?

    // MARK: - Hashable/Equatable default synthesis is fine
    // MARK: - Codable default synthesis is fine (Address, TradeType, JobBudgetType are Codable)
}
