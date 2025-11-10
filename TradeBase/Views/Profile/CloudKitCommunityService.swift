//
//  CloudKitCommunityService.swift
//  TradeBase
//
//  Created by Alex Walters on 02/10/2025.
//

import Foundation
import CloudKit

actor CloudKitCommunityService: CommunityService {

    // MARK: - Schema constants

    private enum RecordType {
        static let post = "Post"
    }

    private enum Field {
        static let authorId = "authorId"
        static let authorDisplayName = "authorDisplayName"
        static let text = "text"
        static let createdAt = "createdAt"
        static let city = "city"
        static let tag = "tag"
        static let isHidden = "isHidden"
    }

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case unauthorizedEditor
        case recordMissing
        case invalidRecordID

        var errorDescription: String? {
            switch self {
            case .unauthorizedEditor: return "You can only modify your own post."
            case .recordMissing: return "Post not found."
            case .invalidRecordID: return "Invalid record identifier."
            }
        }
    }

    // MARK: - CK

    private let container: CKContainer
    private let db: CKDatabase

    init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.db = container.publicCloudDatabase
    }

    // MARK: - Protocol

    func isAccountAvailableForWrites() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    func latest(city: String?) async throws -> [CommunityPost] {
        // Build predicate: isHidden == 0 AND (optional city == value)
        var predicates: [NSPredicate] = [NSPredicate(format: "%K == 0", Field.isHidden)]
        if let c = city?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            predicates.append(NSPredicate(format: "%K == %@", Field.city, c))
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        // Prefer explicit createdAt field; fall back to client-side sort if index isn’t present.
        let query = CKQuery(recordType: RecordType.post, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Field.createdAt, ascending: false)]

        do {
            let records = try await queryAll(query: query, limit: 50)
            return try await mapAndSort(records: records, sortClientSideIfNeeded: false)
        } catch {
            // If the sort index on createdAt is missing, CloudKit commonly throws invalidArguments.
            // Fall back to unsorted query and sort locally by createdAt/creationDate.
            if let ckErr = error as? CKError, ckErr.code == .invalidArguments {
                let fallbackQuery = CKQuery(recordType: RecordType.post, predicate: predicate)
                let records = try await queryAll(query: fallbackQuery, limit: 50)
                return try await mapAndSort(records: records, sortClientSideIfNeeded: true)
            }
            throw error
        }
    }

    func create(text: String,
                city: String,
                tag: String,
                authorId: String,
                authorDisplayName: String) async throws -> CommunityPost {
        // Sanitize inputs
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCity = city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "London" : city
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)

        let record = CKRecord(recordType: RecordType.post)
        record[Field.authorId] = authorId as CKRecordValue
        record[Field.authorDisplayName] = authorDisplayName as CKRecordValue
        record[Field.text] = trimmedText as CKRecordValue
        record[Field.city] = finalCity as CKRecordValue
        record[Field.tag] = trimmedTag as CKRecordValue
        record[Field.createdAt] = Date() as CKRecordValue
        record[Field.isHidden] = NSNumber(value: false)

        let saved = try await saveRecord(record)
        return mapRecord(saved)
    }

    func ensureSubscription(city: String?) async throws {
        // Predicate: isHidden == false (and optional city match)
        var predicates: [NSPredicate] = [NSPredicate(format: "%K == 0", Field.isHidden)]
        var subID = "PostFeed_all"
        if let c = city?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            predicates.append(NSPredicate(format: "%K == %@", Field.city, c))
            subID = "PostFeed_city_\(c)"
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        let subscription = CKQuerySubscription(recordType: RecordType.post,
                                              predicate: predicate,
                                              subscriptionID: subID,
                                              options: [.firesOnRecordCreation])

        let info = CKSubscription.NotificationInfo()
        // Silent push for background refresh; requires Remote notifications background mode to wake app.
        info.shouldSendContentAvailable = true
        // Optional: include a few fields for debugging/foreground notifications if you later add alerts.
        info.desiredKeys = [Field.authorDisplayName, Field.text, Field.city, Field.tag]
        subscription.notificationInfo = info

        try await modifySubscriptions(save: [subscription], deleteIDs: [])
    }

    func update(recordName: String,
                expectedAuthorId: String,
                text: String,
                city: String,
                tag: String) async throws -> CommunityPost {
        let recID = CKRecord.ID(recordName: recordName)
        guard let record = try await fetchRecord(id: recID) else {
            throw ServiceError.recordMissing
        }
        // App-level enforcement: only allow update if the stored authorId matches the expected author.
        let storedAuthor = record[Field.authorId] as? String
        guard storedAuthor == expectedAuthorId else {
            throw ServiceError.unauthorizedEditor
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCity = city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (record[Field.city] as? String ?? "London") : city
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)

        record[Field.text] = trimmedText as CKRecordValue
        record[Field.city] = finalCity as CKRecordValue
        record[Field.tag] = trimmedTag as CKRecordValue

        let saved = try await saveRecord(record)
        return mapRecord(saved)
    }

    func delete(recordName: String, expectedAuthorId: String) async throws {
        let recID = CKRecord.ID(recordName: recordName)
        guard let record = try await fetchRecord(id: recID) else {
            throw ServiceError.recordMissing
        }
        // App-level enforcement: only allow delete if the stored authorId matches the expected author.
        let storedAuthor = record[Field.authorId] as? String
        guard storedAuthor == expectedAuthorId else {
            throw ServiceError.unauthorizedEditor
        }
        try await deleteRecord(id: recID)
    }

    // ADMIN OVERRIDE: delete any post by record name (no author check).
    // CloudKit Post record type must allow this via its security roles.
    func adminDelete(recordName: String) async throws {
        let recID = CKRecord.ID(recordName: recordName)
        // Ensure it exists to mirror normal delete behavior
        guard let _ = try await fetchRecord(id: recID) else {
            throw ServiceError.recordMissing
        }
        try await deleteRecord(id: recID)
    }

    // MARK: - Mapping

    private func mapRecord(_ record: CKRecord) -> CommunityPost {
        let authorId = record[Field.authorId] as? String
        let author = (record[Field.authorDisplayName] as? String) ?? "@User"
        let text = (record[Field.text] as? String) ?? ""
        let city = (record[Field.city] as? String) ?? "Unknown"
        let tag = (record[Field.tag] as? String) ?? ""
        let date = (record[Field.createdAt] as? Date) ?? record.creationDate ?? Date()
        return CommunityPost(
            ckRecordName: record.recordID.recordName,
            authorId: authorId,
            author: author,
            text: text,
            date: date,
            city: city,
            tag: tag
        )
    }

    private func mapAndSort(records: [CKRecord], sortClientSideIfNeeded: Bool) async throws -> [CommunityPost] {
        var posts = records.map { mapRecord($0) }
        if sortClientSideIfNeeded {
            posts.sort { $0.date > $1.date }
        }
        return posts
    }

    // MARK: - CK helpers

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { cont in
            db.save(record) { saved, error in
                if let error { cont.resume(throwing: error); return }
                guard let saved else {
                    cont.resume(throwing: NSError(domain: "CloudKitCommunityService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid record"]))
                    return
                }
                cont.resume(returning: saved)
            }
        }
    }

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

    private func modifySubscriptions(save: [CKSubscription], deleteIDs: [String]) async throws {
        try await withCheckedThrowingContinuation { cont in
            let op = CKModifySubscriptionsOperation(subscriptionsToSave: save, subscriptionIDsToDelete: deleteIDs)
            op.modifySubscriptionsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: ())
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
            self.db.add(op)
        }
    }
}

