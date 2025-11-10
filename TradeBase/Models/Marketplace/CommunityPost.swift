//
//  CommunityPost.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation

struct CommunityPost: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    // Optional CloudKit record identifier for de-duplication and future edit/delete.
    var ckRecordName: String? = nil

    // Stable author identifier (e.g., your app-level profile UUID string).
    // Used for client-side gating of edit/delete actions.
    var authorId: String? = nil

    // Author display name/handle
    var author: String

    // Content
    var text: String
    var date: Date
    var city: String
    var tag: String

    init(ckRecordName: String? = nil,
         authorId: String? = nil,
         author: String,
         text: String,
         date: Date,
         city: String,
         tag: String) {
        self.ckRecordName = ckRecordName
        self.authorId = authorId
        self.author = author
        self.text = text
        self.date = date
        self.city = city
        self.tag = tag
    }
}
