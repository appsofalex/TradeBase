import Foundation
import CloudKit
import UIKit

// Make this the single canonical CloudKitProfileStore and conform to CloudProfileStore.
actor CloudKitProfileStore: CloudProfileStore {
    func fetchUserProfile(identity: String) async throws -> AppState.UserProfile? {
        let recID = recordID(for: identity)
        guard let record = try await fetchRecord(id: recID) else {
            return nil
        }
        var profile = try await userProfile(from: record)

        // Seed avatar cache if needed
        if profile.avatarURL == nil, let asset = record["avatar"] as? CKAsset {
            if let local = try? copyAssetToCache(asset, preferredName: "avatar") {
                profile.avatarURL = local
            }
        }
        return profile
    }
    

    // MARK: - Types

    enum CKErrorLocal: Error, LocalizedError {
        case iCloudUnavailable
        case invalidRecord
        case recordNotFound
        case badData
        case idMappingFailed(String)

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable: return "iCloud is unavailable. Please sign into iCloud."
            case .invalidRecord: return "Invalid CloudKit record."
            case .recordNotFound: return "Record not found."
            case .badData: return "Bad data."
            case .idMappingFailed(let s): return "ID mapping failed: \(s)"
            }
        }
    }

    // MARK: - Init

    private let container: CKContainer
    private let db: CKDatabase
    private let cacheDir: URL
    private let maxCacheBytes: Int64 = 60 * 1024 * 1024 // 60 MB cap

    init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.db = container.privateCloudDatabase

        // Cache directory for downloaded assets
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        let cache = appDir.appendingPathComponent("CloudAssets", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) {
            try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: cache.path) {
            try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: cache.path)
        self.cacheDir = cache
    }

    // MARK: - Helpers

    private func sanitizeRecordName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    private func recordID(for identity: String) -> CKRecord.ID {
        let name = "UserProfile_\(sanitizeRecordName(identity))"
        return CKRecord.ID(recordName: name)
    }

    // MARK: - Account

    func ensureAccountAvailable() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw CKErrorLocal.iCloudUnavailable }
    }

    // MARK: - Profile (CloudProfileStore conformance)

    // Removed duplicate fetchUserProfile returning top-level UserProfile

    func createUserProfile(from seed: AppState.UserProfile, identity: String) async throws {
        let recID = recordID(for: identity)
        let record = try await fetchRecord(id: recID) ?? CKRecord(recordType: "UserProfile", recordID: recID)
        apply(profile: seed, to: record)
        record["appID"] = seed.id.uuidString as CKRecordValue
        _ = try await saveRecord(record)
    }

    func saveProfile(_ profile: AppState.UserProfile, identity: String) async throws {
        let recID = recordID(for: identity)
        let record = try await fetchRecord(id: recID) ?? CKRecord(recordType: "UserProfile", recordID: recID)
        apply(profile: profile, to: record)
        if record["appID"] == nil {
            record["appID"] = profile.id.uuidString as CKRecordValue
        }
        _ = try await saveRecord(record)
    }

    func updateAvatarAsset(from localURL: URL, identity: String) async throws {
        let recID = recordID(for: identity)
        let record = try await fetchRecord(id: recID) ?? CKRecord(recordType: "UserProfile", recordID: recID)
        record["avatar"] = CKAsset(fileURL: localURL)
        _ = try await saveRecord(record)
    }

    func removeAvatarAsset(identity: String) async throws {
        let recID = recordID(for: identity)
        if let record = try await fetchRecord(id: recID) {
            record["avatar"] = nil
            _ = try await saveRecord(record)
        }
        // Purge cached avatar files so any previously cached image doesn't linger.
        purgeAvatarCache()
    }

    func deleteUserProfile(identity: String) async throws {
        let recID = recordID(for: identity)
        try await deleteRecord(id: recID)
    }

    // MARK: - Certifications (CloudProfileStore conformance)

    func fetchCertifications(identity: String) async throws -> [Certification] {
        let ownerRef = CKRecord.Reference(recordID: recordID(for: identity), action: .none)
        let pred = NSPredicate(format: "owner == %@", ownerRef)
        let records = try await query(recordType: "Certification", predicate: pred)
        var result: [Certification] = []
        for r in records {
            if let cert = try await certification(from: r) {
                result.append(cert)
            }
        }
        return result
    }

    func upsertCertification(_ cert: Certification, fileURL: URL?, identity: String) async throws {
        let recID = CKRecord.ID(recordName: cert.id.uuidString)
        let record = try await fetchRecord(id: recID) ?? CKRecord(recordType: "Certification", recordID: recID)
        record["id"] = cert.id.uuidString as CKRecordValue
        record["title"] = cert.title as CKRecordValue
        record["issuer"] = cert.issuer as CKRecordValue
        record["year"] = NSNumber(value: cert.year)
        record["owner"] = CKRecord.Reference(recordID: recordID(for: identity), action: .deleteSelf)

        if let fileURL {
            record["file"] = CKAsset(fileURL: fileURL)
        } else {
            record["file"] = nil
        }

        _ = try await saveRecord(record)
    }

    func deleteCertification(id: UUID) async throws {
        let recID = CKRecord.ID(recordName: id.uuidString)
        try await deleteRecord(id: recID)
    }

    // MARK: - Mapping

    private func userProfile(from record: CKRecord) async throws -> AppState.UserProfile {
        let name = (record["name"] as? String) ?? "User"
        let headline = (record["headline"] as? String) ?? ""
        let bio = (record["bio"] as? String) ?? ""
        let isPremium = (record["isPremium"] as? NSNumber)?.boolValue ?? false

        let tradeTypesStrings: [String] = extractStringArray(record["tradeTypes"])
        let tradeTypes = tradeTypesStrings.compactMap { TradeType(rawValue: $0) }

        let skills: [String] = extractStringArray(record["skills"])

        var avatarURL: URL? = nil
        if let asset = record["avatar"] as? CKAsset {
            avatarURL = try? copyAssetToCache(asset, preferredName: "avatar")
        }

        // Preserve app-level ID if present; otherwise synthesize one
        let appID: UUID
        if let idString = record["appID"] as? String, let uuid = UUID(uuidString: idString) {
            appID = uuid
        } else {
            appID = UUID()
        }

        // City (optional)
        let city = (record["city"] as? String)

        let profile = AppState.UserProfile(
            id: appID,
            name: name,
            headline: headline,
            avatarURL: avatarURL,
            tradeTypes: tradeTypes,
            bio: bio,
            certifications: [],
            reviews: [],
            isPremium: isPremium,
            skills: skills,
            city: (city?.isEmpty == true) ? nil : city,
            username: nil, // usernames removed from app logic
            startYear: nil,
            publicLiabilityFileURL: nil,
            guaranteesFileURL: nil
        )

        return profile
    }

    private func certification(from record: CKRecord) async throws -> Certification? {
        // RecordName should be UUID
        let uuid: UUID
        if let idString = record.recordID.recordName as String?, let u = UUID(uuidString: idString) {
            uuid = u
        } else if let idString = record["id"] as? String, let u = UUID(uuidString: idString) {
            uuid = u
        } else {
            throw CKErrorLocal.idMappingFailed("Certification record missing UUID")
        }

        let title = (record["title"] as? String) ?? "Certification"
        let issuer = (record["issuer"] as? String) ?? ""
        let year = (record["year"] as? NSNumber)?.intValue ?? Calendar.current.component(.year, from: Date())

        var fileURL: URL? = nil
        if let asset = record["file"] as? CKAsset {
            fileURL = try? copyAssetToCache(asset, preferredName: "cert-\(uuid.uuidString)")
        }

        return Certification(id: uuid, title: title, issuer: issuer, year: year, fileURL: fileURL)
    }

    private func apply(profile: AppState.UserProfile, to record: CKRecord) {
        record["name"] = profile.name as CKRecordValue
        record["headline"] = profile.headline as CKRecordValue
        record["bio"] = profile.bio as CKRecordValue
        record["isPremium"] = NSNumber(value: profile.isPremium)

        let tradeStrings = profile.tradeTypes.map { $0.rawValue }
        record["tradeTypes"] = tradeStrings as NSArray

        record["skills"] = profile.skills as NSArray

        // City (optional string; store empty when nil)
        record["city"] = (profile.city ?? "") as CKRecordValue

        // Username removed — no longer read or written
        // record["username"] = nil
    }

    private func extractStringArray(_ value: Any?) -> [String] {
        if let arr = value as? [String] { return arr }
        if let arr = value as? [NSString] { return arr.map { $0 as String } }
        if let arr = value as? NSArray { return arr.compactMap { $0 as? String } }
        return []
    }

    // MARK: - Onboarding/setup flags sync (CloudProfileStore new requirement)

    struct OnboardingFlags {
        var customerOnboardingCompleted: Bool
        var tradespersonOnboardingCompleted: Bool
        var customerSetupCompleted: Bool
        var tradespersonSetupCompleted: Bool
    }

    func fetchOnboardingFlags(identity: String) async throws -> OnboardingFlags? {
        let recID = recordID(for: identity)
        guard let record = try await fetchRecord(id: recID) else { return nil }
        return OnboardingFlags(
            customerOnboardingCompleted: (record["customerOnboardingCompleted"] as? NSNumber)?.boolValue ?? false,
            tradespersonOnboardingCompleted: (record["tradespersonOnboardingCompleted"] as? NSNumber)?.boolValue ?? false,
            customerSetupCompleted: (record["customerSetupCompleted"] as? NSNumber)?.boolValue ?? false,
            tradespersonSetupCompleted: (record["tradespersonSetupCompleted"] as? NSNumber)?.boolValue ?? false
        )
    }

    func saveOnboardingFlags(_ flags: OnboardingFlags, identity: String) async throws {
        let recID = recordID(for: identity)
        let record = try await fetchRecord(id: recID) ?? CKRecord(recordType: "UserProfile", recordID: recID)
        record["customerOnboardingCompleted"] = NSNumber(value: flags.customerOnboardingCompleted)
        record["tradespersonOnboardingCompleted"] = NSNumber(value: flags.tradespersonOnboardingCompleted)
        record["customerSetupCompleted"] = NSNumber(value: flags.customerSetupCompleted)
        record["tradespersonSetupCompleted"] = NSNumber(value: flags.tradespersonSetupCompleted)
        _ = try await saveRecord(record)
    }

    // MARK: - New: resolve identity from appID (fallback for messaging)

    func identity(forAppID appID: UUID) async throws -> String? {
        // Query UserProfile where appID == appID.uuidString, return the identity from the record name.
        let pred = NSPredicate(format: "appID == %@", appID.uuidString)
        let records = try await query(recordType: "UserProfile", predicate: pred)
        guard let record = records.first else { return nil }
        // RecordName is "UserProfile_<sanitized-identity>"
        let name = record.recordID.recordName
        if let range = name.range(of: "UserProfile_") {
            let suffix = name[range.upperBound...]
            // De-sanitize: we can’t perfectly recover special chars, but our sanitize kept alphanumerics, - and _
            // The identity format we use ("apple:", "google:", "email:") consists of allowed chars, so this is fine.
            return String(suffix)
        }
        return nil
    }

    // MARK: - Asset cache

    private func copyAssetToCache(_ asset: CKAsset, preferredName: String) throws -> URL {
        let fm = FileManager.default
        guard let src = asset.fileURL, fm.fileExists(atPath: src.path) else {
            throw CKErrorLocal.badData
        }
        let ext = src.pathExtension.isEmpty ? "bin" : src.pathExtension
        var dest = cacheDir.appendingPathComponent("\(preferredName).\(ext)")
        if fm.fileExists(atPath: dest.path) {
            // Touch modification time to reflect access (LRU)
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
            return dest // idempotent
        }
        try fm.copyItem(at: src, to: dest)

        var rvs = URLResourceValues()
        rvs.isExcludedFromBackup = true
        try? dest.setResourceValues(rvs)

        try? fm.setAttributes([.protectionKey: FileProtectionType.complete, .modificationDate: Date()], ofItemAtPath: dest.path)

        // Enforce budget after each write
        awaitEnforceBudget()
        return dest
    }

    private func awaitEnforceBudget() {
        Task { [weak self] in await self?.enforceCacheBudgetInternal() }
    }

    /// Remove any cached avatar files created by this store.
    private func purgeAvatarCache() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for url in items {
            let name = url.lastPathComponent
            if name.hasPrefix("avatar.") || name.hasPrefix("avatar-") {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - CK helpers (async wrappers)

    private func fetchRecord(id: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { cont in
            db.fetch(withRecordID: id) { record, error in
                if let ckErr = error as? CKError, ckErr.code == .unknownItem {
                    cont.resume(returning: nil)
                    return
                }
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: record)
            }
        }
    }

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { cont in
            db.save(record) { saved, error in
                if let error { cont.resume(throwing: error); return }
                guard let saved else { cont.resume(throwing: CKErrorLocal.invalidRecord); return }
                cont.resume(returning: saved)
            }
        }
    }

    private func deleteRecord(id: CKRecord.ID) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            db.delete(withRecordID: id) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    private func query(recordType: String, predicate: NSPredicate) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { cont in
            let op = CKQueryOperation(query: CKQuery(recordType: recordType, predicate: predicate))
            var results: [CKRecord] = []
            op.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record): results.append(record)
                case .failure: break
                }
            }
            op.queryResultBlock = { result in
                switch result {
                case .success: cont.resume(returning: results)
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            self.db.add(op)
        }
    }

    private func queryAll(query: CKQuery, limit: Int) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { cont in
            var results: [CKRecord] = []
            let op = CKQueryOperation(query: query)
            op.resultsLimit = limit
            op.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    results.append(record)
                }
            }
            op.queryResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: results)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
            self.db.add(op)
        }
    }

    // MARK: - Public: clear cached assets

    func clearCachedAssets() {
        let fm = FileManager.default
        if fm.fileExists(atPath: cacheDir.path) {
            try? fm.removeItem(at: cacheDir)
        }
    }

    // MARK: - Public: enforce cache budget (LRU)
    // Protocol requires async throws; provide a throwing async shim that calls the actor method.

    nonisolated func enforceCacheBudget() async throws {
        await enforceCacheBudgetInternal()
    }

    // Internal actor-isolated non-throwing implementation
    func enforceCacheBudgetInternal() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }

        var total: Int64 = 0
        var records: [(url: URL, size: Int64, mdate: Date)] = []

        for url in items {
            do {
                let vals = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(vals.fileSize ?? 0)
                let mdate = vals.contentModificationDate ?? Date.distantPast
                total += size
                records.append((url, size, mdate))
            } catch { }
        }

        guard total > maxCacheBytes else { return }

        records.sort { $0.mdate < $1.mdate }

        var bytesToFree = total - maxCacheBytes
        for rec in records {
            if bytesToFree <= 0 { break }
            try? fm.removeItem(at: rec.url)
            bytesToFree -= rec.size
        }
    }
}
