//
//  MarketplaceLead.swift
//  TradeBase
//
//  Canonical model for job leads fetched from CloudKit (Public DB, JobLead records).
//  Single authoritative definition (Identifiable, Hashable, Codable).
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
    // e.g. "email:john@doe.com" or "google:abc123"
    var posterIdentity: String? = nil
    // Optional app-level UUID for the poster (if available)
    var posterAppID: UUID? = nil

    // Contact
    // Optional phone number provided by the customer when posting the job.
    // Used for external WhatsApp handoff in LeadDetailView.
    var contactPhone: String? = nil
}

