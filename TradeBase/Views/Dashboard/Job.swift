//
//  Job.swift
//  TradeBase
//

import Foundation

struct Job: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var clientName: String
    var trade: TradeType
    var scheduledStart: Date
    var estimatedHours: Double
    var pay: Money
    var address: Address
    var notes: String
    var isConfirmed: Bool
    var isPremiumLead: Bool = false
}

