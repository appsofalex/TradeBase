import Foundation
import CloudKit

// Public profile adapter that mirrors a subset of private UserProfile fields and document assets.
// Stores assets on the same UserProfile record:
// - "pliAsset" (CKAsset)
// - "guaranteesAsset" (CKAsset)
// Certification documents remain in "Certification" child records with field "file" (CKAsset).
actor CloudKitPublicProfileStore {

    private let container: CKContainer
    private let db: CKDatabase
    private let privateStore: CloudKitProfileStore

    // Local cache dir for downloaded assets so SwiftUI/Quick Look can open by file URL.
    private let cacheDir: URL
    private let maxCacheBytes: Int64 = 60 * 1024 * 1024

    init(container: CKContainer = .default()) {
        self.container = container
        self.db = container.privateCloudDatabase
        self.privateStore = CloudKitProfileStore(containerIdentifier: container.containerIdentifier ?? "iCloud.com.AlexCo.TradeBase")

        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        var cache = appDir.appendingPathComponent("PublicProfileAssets", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) { try? fm.createDirectory(at: appDir, withIntermediateDirectories: true) }
        if !fm.fileExists(atPath: cache.path) { try? fm.createDirectory(at: cache, withIntermediateDirectories: true) }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: cache.path)
        var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true; try? cache.setResourceValues(rvs)
        self.cacheDir = cache
    }

    convenience init(containerIdentifier: String) {
        self.init(container: CKContainer(identifier: containerIdentifier))
    }

    // MARK: - Record ID helpers

    private func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    private func profileRecordID(for identity: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "UserProfile_\(sanitize(identity))")
    }

    // MARK: - Public write API used by AppState/ProfileView

    func upsert(from profile: AppState.UserProfile, identity: String) async throws {
        // Mirror minimal public fields by delegating to private store (already implemented there)
        try await privateStore.saveProfile(profile, identity: identity)
    }

    func updateAvatar(from fileURL: URL, identity: String) async throws {
        try await privateStore.updateAvatarAsset(from: fileURL, identity: identity)
    }

    func removeAvatar(identity: String) async throws {
        try await privateStore.removeAvatarAsset(identity: identity)
    }

    func updatePublicLiability(from fileURL: URL, identity: String) async throws {
        let recID = profileRecordID(for: identity)
        let record = try await fetchOrCreateUserProfile(recID)
        record["pliAsset"] = CKAsset(fileURL: fileURL)
        _ = try await save(record)
    }

    func clearPublicLiability(identity: String) async throws {
        let recID = profileRecordID(for: identity)
        if let record = try await fetch(recID) {
            record["pliAsset"] = nil
            _ = try await save(record)
        }
    }

    func updateGuarantees(from fileURL: URL, identity: String) async throws {
        let recID = profileRecordID(for: identity)
        let record = try await fetchOrCreateUserProfile(recID)
        record["guaranteesAsset"] = CKAsset(fileURL: fileURL)
        _ = try await save(record)
    }

    func clearGuarantees(identity: String) async throws {
        let recID = profileRecordID(for: identity)
        if let record = try await fetch(recID) {
            record["guaranteesAsset"] = nil
            _ = try await save(record)
        }
    }

    // Optional helper if you want to mirror individual certification files immediately.
    func upsertCertificationFile(identity: String, certId: UUID, fileURL: URL?) async throws {
        // We already write the Certification record via private store; nothing else required here.
        // This method exists so the caller can force a fetch refresh pattern if desired.
        _ = (identity, certId, fileURL)
    }

    // MARK: - Public read API

    func fetch(identity: String) async throws -> PublicUserProfile? {
        // 1) Private profile base fields
        guard let user = try await privateStore.fetchUserProfile(identity: identity) else { return nil }

        // 2) Pull compliance asset presence + local URLs
        let recID = profileRecordID(for: identity)
        let record = try await fetch(recID)
        var pliURL: URL? = nil
        var guaranteesURL: URL? = nil
        if let asset = record?["pliAsset"] as? CKAsset, let url = try? copyToCache(asset, preferred: "pli-\(sanitize(identity))") {
            pliURL = url
        }
        if let asset = record?["guaranteesAsset"] as? CKAsset, let url = try? copyToCache(asset, preferred: "guarantees-\(sanitize(identity))") {
            guaranteesURL = url
        }

        // 3) Fetch certification records and map their files to local URLs for native preview
        let certs = try await privateStore.fetchCertifications(identity: identity)
        let certTitles = certs.map { $0.title }

        return PublicUserProfile(
            name: user.name,
            headline: user.headline,
            bio: user.bio,
            city: user.city,
            avatarURL: user.avatarURL,
            mainSkills: user.tradeTypes.first.map { [$0.displayName] } ?? [],
            subSkills: user.skills,
            certificationsSummary: certTitles,
            hasPublicLiability: pliURL != nil,
            hasGuarantees: guaranteesURL != nil
        )
    }

    // MARK: - CK helpers

    private func fetchOrCreateUserProfile(_ id: CKRecord.ID) async throws -> CKRecord {
        if let r = try await fetch(id) { return r }
        return CKRecord(recordType: "UserProfile", recordID: id)
    }

    private func fetch(_ id: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { cont in
            db.fetch(withRecordID: id) { rec, err in
                if let ck = err as? CKError, ck.code == .unknownItem { cont.resume(returning: nil); return }
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: rec)
            }
        }
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { cont in
            db.save(record) { rec, err in
                if let err { cont.resume(throwing: err); return }
                guard let rec else { cont.resume(throwing: NSError(domain: "PublicProfile", code: -1)); return }
                cont.resume(returning: rec)
            }
        }
    }

    private func copyToCache(_ asset: CKAsset, preferred: String) throws -> URL {
        let fm = FileManager.default
        guard let src = asset.fileURL, fm.fileExists(atPath: src.path) else {
            throw NSError(domain: "PublicProfile", code: -10, userInfo: [NSLocalizedDescriptionKey: "Missing asset"])
        }
        let ext = src.pathExtension.isEmpty ? "bin" : src.pathExtension
        var dest = cacheDir.appendingPathComponent(preferred).appendingPathExtension(ext)
        if fm.fileExists(atPath: dest.path) {
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
            return dest
        }
        do { try fm.copyItem(at: src, to: dest) }
        catch { let data = try Data(contentsOf: src); try data.write(to: dest, options: [.atomic]) }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete, .modificationDate: Date()], ofItemAtPath: dest.path)
        var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true; try? dest.setResourceValues(rvs)
        awaitEnforceBudget()
        return dest
    }

    private func awaitEnforceBudget() {
        Task { [weak self] in await self?.enforceCacheBudget() }
    }

    func enforceCacheBudget() async {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var total: Int64 = 0
        var recs: [(URL, Int64, Date)] = []
        for u in items {
            if let vals = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
                total += Int64(vals.fileSize ?? 0)
                recs.append((u, Int64(vals.fileSize ?? 0), vals.contentModificationDate ?? Date.distantPast))
            }
        }
        guard total > maxCacheBytes else { return }
        recs.sort { $0.2 < $1.2 }
        var toFree = total - maxCacheBytes
        for (u, size, _) in recs where toFree > 0 {
            try? fm.removeItem(at: u)
            toFree -= size
        }
    }
}
