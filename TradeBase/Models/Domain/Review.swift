//
//  Review.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

struct Review: Identifiable, Hashable, Codable {
    var id = UUID()
    var author: String
    var rating: Int
    var text: String
    var date: Date
}
