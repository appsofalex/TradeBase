// AppState+Community.swift
import Foundation

extension AppState {

    /// Fetch latest community posts (optionally filtered by city) and update `state.posts`.
    /// Returns an Error if the fetch failed so callers can show a message.
    @discardableResult
    func refreshCommunity(city: String?) async -> Error? {
        do {
            let fetched = try await communityService.latest(city: city)
            await MainActor.run { self.posts = fetched }
            return nil
        } catch {
            return error
        }
    }

    /// Ensure a CloudKit subscription exists to receive silent pushes for new posts.
    func ensureCommunitySubscription(city: String?) async {
        try? await communityService.ensureSubscription(city: city)
    }

    /// Whether CloudKit is available for posting (requires iCloud account on device).
    func isCloudKitAvailableForPosting() async -> Bool {
        await communityService.isAccountAvailableForWrites()
    }

    /// Publish a new community post and return the saved model.
    func publishCommunityPost(text: String, city: String, tag: String) async throws -> CommunityPost {
        guard let authorId = currentAuthIdentity() else {
            throw NSError(domain: "Community", code: 401, userInfo: [NSLocalizedDescriptionKey: "You must be signed in to post."])
        }
        let displayName: String = {
            let n = profile.name
            if n.hasPrefix("@") { return n }
            let compact = n.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            return "@\(compact)"
        }()
        return try await communityService.create(
            text: text,
            city: city,
            tag: tag,
            authorId: authorId,
            authorDisplayName: displayName
        )
    }

    /// Update an existing post (author-only).
    func updateCommunityPost(_ post: CommunityPost) async throws -> CommunityPost {
        guard let recordName = post.ckRecordName else {
            throw NSError(domain: "Community", code: 404, userInfo: [NSLocalizedDescriptionKey: "Missing record identifier."])
        }
        guard let authorId = currentAuthIdentity() else {
            throw NSError(domain: "Community", code: 401, userInfo: [NSLocalizedDescriptionKey: "You must be signed in to edit posts."])
        }
        return try await communityService.update(
            recordName: recordName,
            expectedAuthorId: authorId,
            text: post.text,
            city: post.city,
            tag: post.tag
        )
    }

    /// Delete an existing post (author-only) and remove it from the local list.
    func deleteCommunityPost(_ post: CommunityPost) async throws {
        guard let recordName = post.ckRecordName else {
            throw NSError(domain: "Community", code: 404, userInfo: [NSLocalizedDescriptionKey: "Missing record identifier."])
        }
        guard let authorId = currentAuthIdentity() else {
            throw NSError(domain: "Community", code: 401, userInfo: [NSLocalizedDescriptionKey: "You must be signed in to delete posts."])
        }
        try await communityService.delete(recordName: recordName, expectedAuthorId: authorId)
        await MainActor.run {
            self.posts.removeAll { $0.ckRecordName == recordName }
        }
    }

    /// ADMIN override delete and remove from local list.
    func adminDeleteCommunityPost(_ post: CommunityPost) async throws {
        guard let recordName = post.ckRecordName else {
            throw NSError(domain: "Community", code: 404, userInfo: [NSLocalizedDescriptionKey: "Missing record identifier."])
        }
        try await communityService.adminDelete(recordName: recordName)
        await MainActor.run {
            self.posts.removeAll { $0.ckRecordName == recordName }
        }
    }
}
