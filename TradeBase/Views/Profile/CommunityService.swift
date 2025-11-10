//
//  CommunityService.swift
//  TradeBase
//
//  Created by Alex Walters on 02/10/2025.
//

import Foundation

protocol CommunityService {
    // Read
    func latest(city: String?) async throws -> [CommunityPost]

    // Subscription for silent push on new posts
    func ensureSubscription(city: String?) async throws

    // Capability check
    func isAccountAvailableForWrites() async -> Bool

    // Create
    func create(text: String,
                city: String,
                tag: String,
                authorId: String,
                authorDisplayName: String) async throws -> CommunityPost

    // Update (author-only)
    func update(recordName: String,
                expectedAuthorId: String,
                text: String,
                city: String,
                tag: String) async throws -> CommunityPost

    // Delete (author-only)
    func delete(recordName: String, expectedAuthorId: String) async throws

    // Admin override delete
    func adminDelete(recordName: String) async throws
}
