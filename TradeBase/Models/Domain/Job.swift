//
//  Job.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
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
    var notes: String? = nil
    var isConfirmed: Bool = true
    var isPremiumLead: Bool = false
}
