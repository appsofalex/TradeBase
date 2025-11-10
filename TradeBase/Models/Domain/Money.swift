//
//  Money.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

struct Money: Hashable, Codable {
    var amount: Decimal
    var currency: String = "GBP"
}
