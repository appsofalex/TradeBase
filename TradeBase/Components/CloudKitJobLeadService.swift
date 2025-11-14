private let maxCacheBytes: Int64 = 80 * 1024 * 1024 // 80 MB cap for lead images

//
//  CloudKitJobLeadService.swift
//  TradeBase
//
//  Public CloudKit service for browsing job leads and updating status.
//  Maps CloudKit "JobLead" records to MarketplaceLead.
//

import Foundation
import CloudKit
import CoreLocation

actor CloudKitJobLeadService {

    // MARK: - Schema

    private enum RecordType {
        static let jobLead = "JobLead"
    }

    private enum Field {
        static let id = "id"
        static let ownerUserId = "ownerUserId"
        static let title = "title"
        static let description = "description"
        static let category = "category"
        static let status = "status"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"

        // Location
        static let city = "city"
        static let postcode = "postcode"
        static let location = "location"

        // Media
        static let photoAssets = "photoAssets"

        // Optional/extended
        static let budgetType = "budgetType"
        static let budgetMin = "budgetMin"
        static let budgetMax = "budgetMax"
        static let currency = "currency"
        static let startDate = "startDate"
        static let isUrgent = "isUrgent"
        static let posterAppID = "posterAppID"

        // New: contact phone (used for WhatsApp handoff)
        static let contactPhone = "contactPhone"
    }

    // MARK: - CK

    private let container: CKContainer
    private let db: CKDatabase
    private let cacheDir: URL
    private let maxCacheBytes: Int64 = 120 * 1024 * 1024 // 120 MB cap for lead images

    init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.db = container.publicCloudDatabase

        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        let cache = appDir.appendingPathComponent("LeadAssets", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) { try? fm.createDirectory(at: appDir, withIntermediateDirectories: true) }
        if !fm.fileExists(atPath: cache.path) { try? fm.createDirectory(at: cache, withIntermediateDirectories: true) }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: cache.path)
        self.cacheDir = cache

        print("[CKLeads] init container=\(containerIdentifier) db=public")
    }

    // MARK: - Public API

    func upsert(from listing: JobListing,
                posterIdentity: String?,
                posterAppID: UUID,
                photoFileURLs: [URL] = []) async throws {
        let recID = CKRecord.ID(recordName: listing.id.uuidString)
        let record = try await fetchRecord(id: recID) ?? CKRecord(recordType: RecordType.jobLead, recordID: recID)

        record[Field.id] = listing.id.uuidString as CKRecordValue
        if let posterIdentity { record[Field.ownerUserId] = posterIdentity as CKRecordValue }

        record[Field.title] = listing.title as CKRecordValue
        record[Field.description] = listing.description as CKRecordValue
        record[Field.category] = (listing.category?.rawValue ?? "") as CKRecordValue

        record[Field.status] = listing.status.rawValue as CKRecordValue
        record[Field.createdAt] = listing.createdAt as CKRecordValue
        record[Field.updatedAt] = listing.updatedAt as CKRecordValue

        record[Field.city] = listing.location.city as CKRecordValue
        record[Field.postcode] = listing.location.postcode as CKRecordValue
        if let coord = listing.location.coordinate {
            record[Field.location] = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        } else {
            record[Field.location] = nil
        }

        record[Field.budgetType] = listing.budgetType.rawValue as CKRecordValue
        record[Field.budgetMin] = listing.budgetMin.map { NSDecimalNumber(decimal: $0) }
        record[Field.budgetMax] = listing.budgetMax.map { NSDecimalNumber(decimal: $0) }
        record[Field.currency] = listing.currency as CKRecordValue

        record[Field.startDate] = listing.startDate as CKRecordValue?
        record[Field.isUrgent] = NSNumber(value: listing.isUrgent)
        record[Field.posterAppID] = posterAppID.uuidString as CKRecordValue

        // New: contact phone from listing
        record[Field.contactPhone] = (listing.contactPhone ?? "") as CKRecordValue

        if photoFileURLs.isEmpty {
            record[Field.photoAssets] = nil
        } else {
            record[Field.photoAssets] = photoFileURLs.map { CKAsset(fileURL: $0) } as CKRecordValue
        }

        let saved = try await saveRecord(record)
        print("[CKLeads] upsert OK record=\(saved.recordID.recordName) status=\(listing.status.rawValue) title=\"\(listing.title)\"")
    }

    /// Fetch latest leads. Use strict predicate first, then broad fallback + client-side filter to avoid invalidArguments.
    func latest(limit: Int = 50) async throws -> [MarketplaceLead] {
        // 1) Strict predicate: status == "active"
        let strictPred = NSPredicate(format: "%K == %@", Field.status, JobListingStatus.active.rawValue)
        let strictQuery = CKQuery(recordType: RecordType.jobLead, predicate: strictPred)
        strictQuery.sortDescriptors = [NSSortDescriptor(key: Field.createdAt, ascending: false)]

        print("[CKLeads] latest strict predicate=status == \"active\" limit=\(limit)")
        do {
            let records = try await queryAll(query: strictQuery, limit: limit)
            print("[CKLeads] latest strict fetched records=\(records.count)")
            if !records.isEmpty {
                return try await mapAndSort(records: records, sortClientSideIfNeeded: false)
            }
        } catch {
            // Log but continue to fallback
            print("[CKLeads] latest strict error: \(error) — will fallback")
        }

        // 2) Broad fallback: TRUEPREDICATE (let CloudKit return rows), then FILTER TO ACTIVE before mapping.
        let broadQuery = CKQuery(recordType: RecordType.jobLead, predicate: NSPredicate(value: true))
        print("[CKLeads] latest broad fallback (TRUEPREDICATE)")
        let records = try await queryAll(query: broadQuery, limit: limit)
        print("[CKLeads] latest broad fetched records=\(records.count) — filtering client-side to active")

        // Keep only active records client-side to guarantee Leads shows ONLY posted (active) jobs.
        let activeRecords = records.filter { rec in
            (rec[Field.status] as? String) == JobListingStatus.active.rawValue
        }

        return try await mapAndSort(records: activeRecords, sortClientSideIfNeeded: true)
    }

    func ensureSubscription() async throws {
        let predicate = NSPredicate(format: "%K == %@", Field.status, JobListingStatus.active.rawValue)
        let subID = "JobLead_active_new"

        let subscription = CKQuerySubscription(recordType: RecordType.jobLead,
                                              predicate: predicate,
                                              subscriptionID: subID,
                                              options: [.firesOnRecordCreation])

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.desiredKeys = [Field.title, Field.city, Field.postcode]
        subscription.notificationInfo = info

        try await modifySubscriptions(save: [subscription], deleteIDs: [])
        print("[CKLeads] subscription ensured id=\(subID)")
    }

    func updateStatus(recordName: String, to newStatus: JobListingStatus) async throws {
        let recID = CKRecord.ID(recordName: recordName)
        guard let record = try await fetchRecord(id: recID) else { return }
        record[Field.status] = newStatus.rawValue as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        let saved = try await saveRecord(record)
        print("[CKLeads] updateStatus OK record=\(saved.recordID.recordName) -> \(newStatus.rawValue)")
    }

    // MARK: - Mapping (updated)
    private func mapAndSort(records: [CKRecord], sortClientSideIfNeeded: Bool) async throws -> [MarketplaceLead] {
        var leads: [MarketplaceLead] = []
        leads.reserveCapacity(records.count)
        for r in records {
            if let lead = try await mapRecord(r) {
                leads.append(lead)
            }
        }
        if sortClientSideIfNeeded {
            leads.sort { $0.createdAt > $1.createdAt }
        }
        return leads
    }

    private func mapRecord(_ record: CKRecord) async throws -> MarketplaceLead? {
        let id: UUID = {
            if let s = record[Field.id] as? String, let u = UUID(uuidString: s) { return u }
            if let u = UUID(uuidString: record.recordID.recordName) { return u }
            return UUID()
        }()

        let title = (record[Field.title] as? String) ?? ""
        let desc = (record[Field.description] as? String) ?? ""

        let catString = (record[Field.category] as? String) ?? ""
        let category = TradeType(rawValue: catString)

        let createdAt = (record[Field.createdAt] as? Date) ?? record.creationDate ?? Date()
        let updatedAt = (record[Field.updatedAt] as? Date) ?? record.modificationDate ?? createdAt

        let posterIdentity = record[Field.ownerUserId] as? String
        let posterAppID: UUID? = (record[Field.posterAppID] as? String).flatMap(UUID.init(uuidString:))

        let city = (record[Field.city] as? String) ?? ""
        let postcode = (record[Field.postcode] as? String) ?? ""
        let coord: CLLocationCoordinate2D? = (record[Field.location] as? CLLocation)?.coordinate
        let addr = Address(line1: "", city: city, postcode: postcode, coordinate: coord)

        let budgetTypeRaw = (record[Field.budgetType] as? String) ?? JobBudgetType.fixed.rawValue
        let budgetType = JobBudgetType(rawValue: budgetTypeRaw) ?? .fixed

        let currency = (record[Field.currency] as? String) ?? "GBP"
        let budgetMin = decimal(from: record[Field.budgetMin])
        let budgetMax = decimal(from: record[Field.budgetMax])

        let startDate = (record[Field.startDate] as? Date)
        let isUrgent = (record[Field.isUrgent] as? NSNumber)?.boolValue ?? false

        var photoURLs: [URL] = []
        if let assets = record[Field.photoAssets] as? [CKAsset] {
            for (idx, asset) in assets.enumerated() {
                if let cached = try? copyAssetToCache(asset, preferredName: "lead-\(id.uuidString)-\(idx)") {
                    photoURLs.append(cached)
                }
            }
        }

        // New: contact phone (empty string stored means nil)
        let phoneRaw = (record[Field.contactPhone] as? String) ?? ""
        let contactPhone = phoneRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phoneRaw

        return MarketplaceLead(
            id: id,
            title: title,
            category: category,
            description: desc,
            location: addr,
            budgetType: budgetType,
            budgetMin: budgetMin,
            budgetMax: budgetMax,
            currency: currency,
            startDate: startDate,
            isUrgent: isUrgent,
            photoURLs: photoURLs,
            createdAt: createdAt,
            updatedAt: updatedAt,
            posterIdentity: posterIdentity,
            posterAppID: posterAppID,
            contactPhone: contactPhone
        )
    }

    // MARK: - Helpers (unchanged)
    private func decimal(from any: Any?) -> Decimal? {
        switch any {
        case let n as NSNumber: return Decimal(string: n.stringValue)
        case let s as String: return Decimal(string: s)
        default: return nil
        }
    }

    private func copyAssetToCache(_ asset: CKAsset, preferredName: String) throws -> URL {
        let fm = FileManager.default
        guard let src = asset.fileURL, fm.fileExists(atPath: src.path) else {
            throw NSError(domain: "CloudKitJobLeadService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Missing asset file"])
        }
        let ext = src.pathExtension.isEmpty ? "jpg" : src.pathExtension
        var dest = cacheDir.appendingPathComponent("\(preferredName).\(ext)")
        if fm.fileExists(atPath: dest.path) {
            // Touch modification date to reflect access for LRU
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
            return dest
        }
        do { try fm.copyItem(at: src, to: dest) }
        catch { let data = try Data(contentsOf: src); try data.write(to: dest, options: [.atomic]) }
        var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true; try? dest.setResourceValues(rvs)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete, .modificationDate: Date()], ofItemAtPath: dest.path)
        // Enforce budget after each write
        awaitEnforceBudget()
        return dest
    }

    private func awaitEnforceBudget() {
        Task { [weak self] in await self?.enforceCacheBudget() }
    }

    // MARK: - CK helpers (unchanged)
    private func fetchRecord(id: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { cont in
            db.fetch(withRecordID: id) { record, error in
                if let ckErr = error as? CKError, ckErr.code == .unknownItem { cont.resume(returning: nil); return }
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: record)
            }
        }
    }

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { cont in
            db.save(record) { saved, error in
                if let error { cont.resume(throwing: error); return }
                guard let saved else {
                    cont.resume(throwing: NSError(domain: "CloudKitJobLeadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid record"]))
                    return
                }
                cont.resume(returning: saved)
            }
        }
    }

    private func queryAll(query: CKQuery, limit: Int) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { cont in
            var results: [CKRecord] = []
            let op = CKQueryOperation(query: query)
            op.resultsLimit = limit
            op.recordMatchedBlock = { _, result in if case .success(let record) = result { results.append(record) } }
            op.queryResultBlock = { result in
                switch result {
                case .success: cont.resume(returning: results)
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            self.db.add(op)
        }
    }

    private func modifySubscriptions(save: [CKSubscription], deleteIDs: [String]) async throws {
        try await withCheckedThrowingContinuation { cont in
            let op = CKModifySubscriptionsOperation(subscriptionsToSave: save, subscriptionIDsToDelete: deleteIDs)
            op.modifySubscriptionsResultBlock = { result in
                switch result {
                case .success: cont.resume(returning: ())
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            self.db.add(op)
        }
    }

    // MARK: - Public: clear cached lead assets

    func clearCachedLeadAssets() {
        let fm = FileManager.default
        if fm.fileExists(atPath: cacheDir.path) {
            try? fm.removeItem(at: cacheDir)
        }
    }

    // MARK: - Public: enforce cache budget (LRU)

    func enforceCacheBudget() {
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

