import Foundation
import CloudKit
import UIKit

// Production-ready CloudKit-backed implementation that conforms to your existing MessagingService API.
// It uses the public database and your Conversation/Message record types.
// Notes:
// - Per-user maps (unreadMap/archivedMap/deletedMap) are stored as JSON strings in CloudKit and mapped to dictionaries in code.
// - Media assets are uploaded to CloudKit and also cached locally under Application Support/TradeBase/MessagingAssets
//   so ChatView can continue to display via mediaLocalURL/mediaThumbnailURL.
// - Live updates are provided via AsyncStreams refreshed on demand; CKQuerySubscriptions are created for silent pushes
//   (app must handle push to trigger refresh; we also refetch on observe start).
actor CloudKitMessagingServiceCK: MessagingService {

    // MARK: - Schema

    private enum RecordType {
        static let conversation = "Conversation"
        static let message = "Message"
    }

    private enum ConversationField {
        static let participantIds = "participantIds"     // [String]
        static let lastMessageText = "lastMessageText"   // String
        static let lastMessageAt = "lastMessageAt"       // Date
        static let unreadMap = "unreadMap"               // String (JSON)
        static let archivedMap = "archivedMap"           // String (JSON)
        static let deletedMap = "deletedMap"             // String (JSON)
        static let leadId = "leadId"                     // String
    }

    private enum MessageField {
        static let conversationRef = "conversation"      // Reference
        static let senderId = "senderId"                 // String
        static let text = "text"                         // String
        static let sentAt = "sentAt"                     // Date
        static let readBy = "readBy"                     // [String]
        // Media
        static let mediaType = "mediaType"               // String ("photo"|"video")
        static let mediaAsset = "mediaAsset"             // Asset
        static let mediaThumbnail = "mediaThumbnail"     // Asset (optional, videos)
        static let mediaWidth = "mediaWidth"             // Double
        static let mediaHeight = "mediaHeight"           // Double
        static let mediaDuration = "mediaDuration"       // Double
    }

    // MARK: - CloudKit

    private let container: CKContainer
    private let db: CKDatabase

    // MARK: - Local cache for downloaded media (so UI can show via file URLs)

    private let cacheDir: URL
    private let maxCacheBytes: Int64 = 120 * 1024 * 1024 // 120 MB

    // MARK: - Streams

    private var conversationStreams: [String: AsyncStream<[Conversation]>.Continuation] = [:]   // userId -> continuation
    private var messageStreams: [String: AsyncStream<[Message]>.Continuation] = [:]             // conversationId -> continuation

    init(containerIdentifier: String = "iCloud.com.AlexCo.TradeBase") {
        self.container = CKContainer(identifier: containerIdentifier)
        self.db = container.publicCloudDatabase

        // Prepare cache folder
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        var cache = appDir.appendingPathComponent("MessagingAssets", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) { try? fm.createDirectory(at: appDir, withIntermediateDirectories: true) }
        if !fm.fileExists(atPath: cache.path) { try? fm.createDirectory(at: cache, withIntermediateDirectories: true) }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: cache.path)
        var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true
        try? cache.setResourceValues(rvs)
        self.cacheDir = cache
    }

    // MARK: - MessagingService

    func getOrCreateDirectConversation(currentUserId: String, otherUserId: String, leadId: String?) async throws -> Conversation {
        if let existing = try await findDirectConversation(between: currentUserId, and: otherUserId, leadId: leadId) {
            return existing
        }
        // Create new Conversation record
        let rec = CKRecord(recordType: RecordType.conversation)
        rec[ConversationField.participantIds] = [currentUserId, otherUserId] as CKRecordValue
        rec[ConversationField.lastMessageText] = "" as CKRecordValue
        rec[ConversationField.lastMessageAt] = Date() as CKRecordValue
        rec[ConversationField.leadId] = (leadId ?? "") as CKRecordValue

        let unread: [String: Int] = [currentUserId: 0, otherUserId: 0]
        let archived: [String: Bool] = [:]
        let deleted: [String: Bool] = [:]
        rec[ConversationField.unreadMap] = try encodeJSON(unread) as CKRecordValue
        rec[ConversationField.archivedMap] = try encodeJSON(archived) as CKRecordValue
        rec[ConversationField.deletedMap] = try encodeJSON(deleted) as CKRecordValue

        let saved = try await saveRecord(rec)
        let convo = try await mapConversation(saved)
        // Notify both participants streams
        notifyConversationsChanged(for: currentUserId)
        notifyConversationsChanged(for: otherUserId)
        return convo
    }

    func fetchConversations(for userId: String) async throws -> [Conversation] {
        // Predicate: participantIds CONTAINS userId AND NOT deletedMap[userId] == true
        // Since deletedMap is a JSON string, we can't query inside it; we fetch by participantIds and filter client-side.
        let pred = NSPredicate(format: "%K CONTAINS %@", ConversationField.participantIds, userId)
        let query = CKQuery(recordType: RecordType.conversation, predicate: pred)
        query.sortDescriptors = [NSSortDescriptor(key: ConversationField.lastMessageAt, ascending: false)]

        let records = try await queryAll(query: query, limit: 200)
        // Use a for loop to await async mapping
        var convos: [Conversation] = []
        convos.reserveCapacity(records.count)
        for r in records {
            if let c = try? await mapConversation(r) {
                convos.append(c)
            }
        }
        // Client-side filter for soft delete
        let filtered = convos.filter { !$0.isDeleted(for: userId) }
        return filtered.sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    func fetchMessages(conversationId: String, before: Date?, limit: Int) async throws -> [Message] {
        let convRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: conversationId), action: .none)
        var pred = NSPredicate(format: "%K == %@", MessageField.conversationRef, convRef)
        if let before {
            pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
                pred,
                NSPredicate(format: "%K < %@", MessageField.sentAt, before as NSDate)
            ])
        }
        let query = CKQuery(recordType: RecordType.message, predicate: pred)
        query.sortDescriptors = [NSSortDescriptor(key: MessageField.sentAt, ascending: true)]
        let records = try await queryAll(query: query, limit: limit)
        let msgs = try await mapMessages(records)
        return msgs
    }

    func sendMessage(conversationId: String, text: String, senderId: String) async throws -> Message {
        let now = Date()

        // Create Message
        let msgRec = CKRecord(recordType: RecordType.message)
        msgRec[MessageField.conversationRef] = CKRecord.Reference(recordID: CKRecord.ID(recordName: conversationId), action: .none)
        msgRec[MessageField.senderId] = senderId as CKRecordValue
        msgRec[MessageField.text] = text as CKRecordValue
        msgRec[MessageField.sentAt] = now as CKRecordValue
        msgRec[MessageField.readBy] = [senderId] as CKRecordValue

        let savedMsg = try await saveRecord(msgRec)

        // Update Conversation lastMessage*, unreadMap
        try await bumpConversationAfterSend(conversationId: conversationId, sentText: text, sentAt: now, senderId: senderId, mediaType: nil)

        let mapped = try await mapMessage(savedMsg)
        // Notify streams
        notifyMessagesChanged(for: conversationId)
        if let conv = try? await fetchConversationByID(conversationId) {
            for uid in conv.participantIds { notifyConversationsChanged(for: uid) }
        }
        return mapped
    }

    func sendMediaMessage(conversationId: String, senderId: String, fileURL: URL, kind: MediaKind, meta: MediaMeta?) async throws -> Message {
        let now = Date()
        // Upload asset(s)
        let msgRec = CKRecord(recordType: RecordType.message)
        msgRec[MessageField.conversationRef] = CKRecord.Reference(recordID: CKRecord.ID(recordName: conversationId), action: .none)
        msgRec[MessageField.senderId] = senderId as CKRecordValue
        msgRec[MessageField.text] = "" as CKRecordValue
        msgRec[MessageField.sentAt] = now as CKRecordValue
        msgRec[MessageField.readBy] = [senderId] as CKRecordValue
        msgRec[MessageField.mediaType] = kind.rawValue as CKRecordValue
        msgRec[MessageField.mediaAsset] = CKAsset(fileURL: fileURL)

        if let w = meta?.width { msgRec[MessageField.mediaWidth] = NSNumber(value: w) }
        if let h = meta?.height { msgRec[MessageField.mediaHeight] = NSNumber(value: h) }
        if let d = meta?.duration { msgRec[MessageField.mediaDuration] = NSNumber(value: d) }

        // If a sibling thumb.jpg exists, attach it
        let thumb = fileURL.deletingPathExtension().appendingPathExtension("thumb.jpg")
        if FileManager.default.fileExists(atPath: thumb.path) {
            msgRec[MessageField.mediaThumbnail] = CKAsset(fileURL: thumb)
        }

        let savedMsg = try await saveRecord(msgRec)

        // Update Conversation lastMessage*, unreadMap
        try await bumpConversationAfterSend(conversationId: conversationId, sentText: (kind == .photo ? "Photo" : "Video"), sentAt: now, senderId: senderId, mediaType: kind.rawValue)

        let mapped = try await mapMessage(savedMsg)
        // Notify streams
        notifyMessagesChanged(for: conversationId)
        if let conv = try? await fetchConversationByID(conversationId) {
            for uid in conv.participantIds { notifyConversationsChanged(for: uid) }
        }
        return mapped
    }

    func markConversationRead(conversationId: String, userId: String) async throws {
        guard let rec = try await fetchRecord(id: CKRecord.ID(recordName: conversationId)) else { return }
        var unread = try decodeJSONDictionaryInt(rec[ConversationField.unreadMap] as? String)
        unread[userId] = 0
        rec[ConversationField.unreadMap] = try encodeJSON(unread) as CKRecordValue
        _ = try await saveRecord(rec)
        notifyConversationsChanged(for: userId)
    }

    func totalUnreadCount(for userId: String) async throws -> Int {
        let convs = try await fetchConversations(for: userId)
        return convs.reduce(0) { $0 + max(0, $1.unreadMap[userId] ?? 0) }
    }

    func observeConversations(for userId: String) -> AsyncStream<[Conversation]> {
        AsyncStream { continuation in
            // We’re in a nonisolated context; hop back to the actor to mutate state.
            Task { [weak self] in
                await self?.setConversationContinuation(continuation, for: userId)
                let current = try? await self?.fetchConversations(for: userId)
                continuation.yield(current ?? [])
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeConversationContinuation(for: userId) }
            }
        }
    }

    func observeMessages(conversationId: String) -> AsyncStream<[Message]> {
        AsyncStream { continuation in
            Task { [weak self] in
                await self?.setMessageContinuation(continuation, for: conversationId)
                let msgs = try? await self?.fetchMessages(conversationId: conversationId, before: nil, limit: 500)
                continuation.yield(msgs ?? [])
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeMessageContinuation(for: conversationId) }
            }
        }
    }

    func ensureSubscriptions(for userId: String) async throws {
        // 1) New conversations involving the user
        let convPred = NSPredicate(format: "%K CONTAINS %@", ConversationField.participantIds, userId)
        let convSubID = "conv_new_\(sanitize(userId))"
        let convSub = CKQuerySubscription(recordType: RecordType.conversation,
                                          predicate: convPred,
                                          subscriptionID: convSubID,
                                          options: [.firesOnRecordCreation, .firesOnRecordUpdate])

        // 2) New messages for any conversation (we filter by desiredKeys and let app refresh specific convs)
        // A more precise approach would be one subscription per conversation, but that scales poorly.
        let msgPred = NSPredicate(value: true)
        let msgSubID = "msg_new_all"
        let msgSub = CKQuerySubscription(recordType: RecordType.message,
                                         predicate: msgPred,
                                         subscriptionID: msgSubID,
                                         options: [.firesOnRecordCreation])

        let info1 = CKSubscription.NotificationInfo()
        info1.shouldSendContentAvailable = true
        info1.desiredKeys = [ConversationField.participantIds, ConversationField.lastMessageAt, ConversationField.lastMessageText]
        convSub.notificationInfo = info1

        let info2 = CKSubscription.NotificationInfo()
        info2.shouldSendContentAvailable = true
        info2.desiredKeys = [MessageField.conversationRef, MessageField.sentAt]
        msgSub.notificationInfo = info2

        try await modifySubscriptions(save: [convSub, msgSub], deleteIDs: [])
    }

    func setArchived(conversationId: String, userId: String, archived: Bool) async throws {
        guard let rec = try await fetchRecord(id: CKRecord.ID(recordName: conversationId)) else { return }
        var archivedMap = try decodeJSONDictionaryBool(rec[ConversationField.archivedMap] as? String)
        archivedMap[userId] = archived
        rec[ConversationField.archivedMap] = try encodeJSON(archivedMap) as CKRecordValue
        _ = try await saveRecord(rec)
        notifyConversationsChanged(for: userId)
    }

    func softDelete(conversationId: String, userId: String) async throws {
        guard let rec = try await fetchRecord(id: CKRecord.ID(recordName: conversationId)) else { return }
        var deletedMap = try decodeJSONDictionaryBool(rec[ConversationField.deletedMap] as? String)
        deletedMap[userId] = true
        rec[ConversationField.deletedMap] = try encodeJSON(deletedMap) as CKRecordValue
        _ = try await saveRecord(rec)
        notifyConversationsChanged(for: userId)
    }

    // MARK: - Helpers: actor-isolated continuation setters

    private func setConversationContinuation(_ cont: AsyncStream<[Conversation]>.Continuation, for userId: String) {
        conversationStreams[userId] = cont
    }

    private func removeConversationContinuation(for userId: String) {
        conversationStreams[userId] = nil
    }

    private func setMessageContinuation(_ cont: AsyncStream<[Message]>.Continuation, for conversationId: String) {
        messageStreams[conversationId] = cont
    }

    private func removeMessageContinuation(for conversationId: String) {
        messageStreams[conversationId] = nil
    }

    // MARK: - Helpers: conversation find/update

    private func findDirectConversation(between a: String, and b: String, leadId: String?) async throws -> Conversation? {
        // Query for any conversation containing user A; filter client-side for exact pair + leadId
        let pred = NSPredicate(format: "%K CONTAINS %@", ConversationField.participantIds, a)
        let query = CKQuery(recordType: RecordType.conversation, predicate: pred)
        let records = try await queryAll(query: query, limit: 200)
        for r in records {
            let conv = try await mapConversation(r)
            if Set(conv.participantIds) == Set([a, b]), conv.leadId == leadId {
                return conv
            }
        }
        return nil
    }

    private func fetchConversationByID(_ id: String) async throws -> Conversation? {
        guard let rec = try await fetchRecord(id: CKRecord.ID(recordName: id)) else { return nil }
        return try await mapConversation(rec)
    }

    private func bumpConversationAfterSend(conversationId: String, sentText: String, sentAt: Date, senderId: String, mediaType: String?) async throws {
        guard let rec = try await fetchRecord(id: CKRecord.ID(recordName: conversationId)) else { return }
        rec[ConversationField.lastMessageText] = (mediaType == nil ? sentText : (mediaType == "photo" ? "Photo" : "Video")) as CKRecordValue
        rec[ConversationField.lastMessageAt] = sentAt as CKRecordValue

        // Update unread map: +1 for others, 0 for sender
        var unread = try decodeJSONDictionaryInt(rec[ConversationField.unreadMap] as? String)
        let participants = (rec[ConversationField.participantIds] as? [String]) ?? []
        for uid in participants where uid != senderId {
            unread[uid] = max(0, (unread[uid] ?? 0)) + 1
        }
        unread[senderId] = 0
        rec[ConversationField.unreadMap] = try encodeJSON(unread) as CKRecordValue

        _ = try await saveRecord(rec)
    }

    // MARK: - Mapping

    // Canonicalization: ensure IDs are in the same format AppState.currentAuthIdentity() returns.
    // If an ID already contains a known prefix, keep it. If it looks like an email, prefix with "email:" and lowercase.
    // Otherwise, leave as-is (you can extend with apple/google heuristics if needed).
    private func canonicalIdentity(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }
        // Already namespaced?
        if trimmed.contains(":") {
            // Best-effort: normalize email part to lowercase if it's an email namespace
            if trimmed.lowercased().hasPrefix("email:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    return "email:\(parts[1].lowercased())"
                }
            }
            return trimmed
        }
        // Email heuristic
        if trimmed.contains("@") {
            return "email:\(trimmed.lowercased())"
        }
        // Unknown raw ID; keep as-is (you may later add mapping for Apple/Google raw IDs if you ever stored them without prefixes)
        return trimmed
    }

    private func mapConversation(_ record: CKRecord) async throws -> Conversation {
        let id = record.recordID.recordName
        let rawParticipants = (record[ConversationField.participantIds] as? [String]) ?? []
        // Normalize participant IDs
        let participants = rawParticipants.map { canonicalIdentity($0) }

        let lastText = (record[ConversationField.lastMessageText] as? String) ?? ""
        let lastAt = (record[ConversationField.lastMessageAt] as? Date) ?? record.modificationDate ?? Date()
        let leadId = (record[ConversationField.leadId] as? String).flatMap { $0.isEmpty ? nil : $0 }

        // The unread/archived/deleted maps are keyed by userId; normalize keys to match canonical identities
        let unreadRaw = try decodeJSONDictionaryInt(record[ConversationField.unreadMap] as? String)
        let archivedRaw = try decodeJSONDictionaryBool(record[ConversationField.archivedMap] as? String)
        let deletedRaw = try decodeJSONDictionaryBool(record[ConversationField.deletedMap] as? String)

        var unread: [String: Int] = [:]
        for (k, v) in unreadRaw { unread[canonicalIdentity(k)] = v }

        var archived: [String: Bool] = [:]
        for (k, v) in archivedRaw { archived[canonicalIdentity(k)] = v }

        var deleted: [String: Bool] = [:]
        for (k, v) in deletedRaw { deleted[canonicalIdentity(k)] = v }

        return Conversation(
            id: id,
            participantIds: participants,
            lastMessageText: lastText,
            lastMessageAt: lastAt,
            unreadMap: unread,
            leadId: leadId,
            archivedMap: archived,
            deletedMap: deleted
        )
    }

    private func mapMessages(_ records: [CKRecord]) async throws -> [Message] {
        var result: [Message] = []
        result.reserveCapacity(records.count)
        for r in records {
            if let m = try? await mapMessage(r) {
                result.append(m)
            }
        }
        return result.sorted { (l, r) in
            if l.sentAt != r.sentAt { return l.sentAt < r.sentAt }
            return l.id < r.id
        }
    }

    private func mapMessage(_ record: CKRecord) async throws -> Message {
        let id = record.recordID.recordName
        let convRef = (record[MessageField.conversationRef] as? CKRecord.Reference)?.recordID.recordName ?? ""
        let senderRaw = (record[MessageField.senderId] as? String) ?? ""
        // Normalize sender ID
        let sender = canonicalIdentity(senderRaw)

        let text = (record[MessageField.text] as? String) ?? ""
        let sentAt = (record[MessageField.sentAt] as? Date) ?? record.creationDate ?? Date()

        // Normalize readBy list
        let readByRaw = (record[MessageField.readBy] as? [String]) ?? []
        let readBy = readByRaw.map { canonicalIdentity($0) }

        var mediaType: String? = record[MessageField.mediaType] as? String
        var localURL: URL? = nil
        var thumbURL: URL? = nil

        if let asset = record[MessageField.mediaAsset] as? CKAsset, let cached = try? copyAssetToCache(asset, preferredName: "media-\(id)") {
            localURL = cached
        }
        if let thumb = record[MessageField.mediaThumbnail] as? CKAsset, let cached = try? copyAssetToCache(thumb, preferredName: "thumb-\(id)") {
            thumbURL = cached
        }
        // If there is no mediaAsset but mediaType is set, clear it to avoid UI showing placeholder
        if mediaType != nil && localURL == nil {
            mediaType = nil
        }

        let w = (record[MessageField.mediaWidth] as? NSNumber)?.doubleValue
        let h = (record[MessageField.mediaHeight] as? NSNumber)?.doubleValue
        let d = (record[MessageField.mediaDuration] as? NSNumber)?.doubleValue

        return Message(
            id: id,
            conversationId: convRef,
            senderId: sender,
            text: text,
            sentAt: sentAt,
            readBy: readBy,
            mediaType: mediaType,
            mediaLocalURL: localURL,
            mediaThumbnailURL: thumbURL,
            mediaWidth: w,
            mediaHeight: h,
            mediaDuration: d
        )
    }

    // MARK: - JSON helpers for per-user maps

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func decodeJSONDictionaryInt(_ s: String?) throws -> [String: Int] {
        guard let s, let data = s.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func decodeJSONDictionaryBool(_ s: String?) throws -> [String: Bool] {
        guard let s, let data = s.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Bool].self, from: data)) ?? [:]
    }

    // MARK: - Cache helpers

    private func copyAssetToCache(_ asset: CKAsset, preferredName: String) throws -> URL {
        let fm = FileManager.default
        guard let src = asset.fileURL, fm.fileExists(atPath: src.path) else {
            throw NSError(domain: "CloudKitMessagingServiceCK", code: -10, userInfo: [NSLocalizedDescriptionKey: "Missing asset file"])
        }
        let ext = src.pathExtension.isEmpty ? "bin" : src.pathExtension
        var dest = cacheDir.appendingPathComponent("\(preferredName).\(ext)")
        if fm.fileExists(atPath: dest.path) {
            // Touch mdate for LRU
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
            return dest
        }
        do { try fm.copyItem(at: src, to: dest) }
        catch { let data = try Data(contentsOf: src); try data.write(to: dest, options: [.atomic]) }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete, .modificationDate: Date()], ofItemAtPath: dest.path)
        var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true; try? dest.setResourceValues(rvs)
        awaitEnforceCacheBudget()
        return dest
    }

    private func awaitEnforceCacheBudget() {
        Task { [weak self] in await self?.enforceCacheBudget() }
    }

    private func enforceCacheBudget() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        var total: Int64 = 0
        var records: [(url: URL, size: Int64, mdate: Date)] = []
        for url in items {
            if let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
                let size = Int64(vals.fileSize ?? 0)
                let mdate = vals.contentModificationDate ?? Date.distantPast
                total += size
                records.append((url, size, mdate))
            }
        }
        guard total > maxCacheBytes else { return }
        records.sort { $0.mdate < $1.mdate }
        var toFree = total - maxCacheBytes
        for rec in records {
            if toFree <= 0 { break }
            try? fm.removeItem(at: rec.url)
            toFree -= rec.size
        }
    }

    // MARK: - Streams notifications

    private func notifyConversationsChanged(for userId: String) {
        Task {
            let current = try? await fetchConversations(for: userId)
            conversationStreams[userId]?.yield(current ?? [])
        }
    }

    private func notifyMessagesChanged(for conversationId: String) {
        Task {
            let msgs = try? await fetchMessages(conversationId: conversationId, before: nil, limit: 500)
            messageStreams[conversationId]?.yield(msgs ?? [])
        }
    }

    // MARK: - CK helpers

    private func fetchRecord(id: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { cont in
            db.fetch(withRecordID: id) { record, error in
                if let ck = error as? CKError, ck.code == .unknownItem { cont.resume(returning: nil); return }
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
                    cont.resume(throwing: NSError(domain: "CloudKitMessagingServiceCK", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid record"]))
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

    // MARK: - Utils

    private func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
