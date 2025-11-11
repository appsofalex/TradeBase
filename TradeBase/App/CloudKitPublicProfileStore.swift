import Foundation
import CloudKit

// Minimal adapter that reuses the private CloudKitProfileStore to resolve names/avatars,
// and maps them into PublicUserProfile for read-only display.
actor CloudKitPublicProfileStore {

    private let container: CKContainer
    // Reuse your existing private profile store for fetching
    private let privateStore: CloudKitProfileStore

    // Default to the app’s default container
    init(container: CKContainer = .default()) {
        self.container = container
        self.privateStore = CloudKitProfileStore(containerIdentifier: container.containerIdentifier ?? "iCloud.com.AlexCo.TradeBase")
    }

    // Matches AppState usage with containerIdentifier
    convenience init(containerIdentifier: String) {
        self.init(container: CKContainer(identifier: containerIdentifier))
    }

    // Upsert minimal public fields from a private profile into the Public DB.
    // For Option A (quick path), we don’t actually write to a public DB — we no-op.
    func upsert(from profile: AppState.UserProfile, identity: String) async throws {
        _ = (profile, identity)
        // No-op: we rely on the private profile as the source of truth for now.
    }

    // Upload/associate a public avatar asset for the identity.
    // For Option A, no-op (avatar already lives in private store and is readable locally).
    func updateAvatar(from fileURL: URL, identity: String) async throws {
        _ = (fileURL, identity)
        // No-op
    }

    // Remove the public avatar for the identity (no-op for Option A).
    func removeAvatar(identity: String) async throws {
        _ = identity
        // No-op
    }

    // Optional: enforce local cache budget for any public-profile assets you store on disk.
    func enforceCacheBudget() async throws {
        // No-op
    }

    // Resolve a display-ready PublicUserProfile by fetching the private profile
    // and mapping its fields. This is the key to showing a real name instead of the UID.
    func fetch(identity: String) async throws -> PublicUserProfile? {
        // Ask the private store for the user profile
        guard let user = try await privateStore.fetchUserProfile(identity: identity) else {
            return nil
        }

        // Map to PublicUserProfile used by your public views
        let mainSkills = user.tradeTypes.first.map { [$0.displayName] } ?? []
        let subs = user.skills
        let certTitles = user.certifications.map { $0.title }

        return PublicUserProfile(
            name: user.name,
            headline: user.headline,
            bio: user.bio,
            city: user.city,
            avatarURL: user.avatarURL,
            mainSkills: mainSkills,
            subSkills: subs,
            certificationsSummary: certTitles,
            hasPublicLiability: false,
            hasGuarantees: false
        )
    }
}
