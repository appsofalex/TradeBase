import Foundation
import CloudKit
import UIKit

// Lightweight stub that satisfies AppState and ChatView. Replace internals with real CloudKit logic later.
final class CloudKitMessagingService: MessagingService {

    // MARK: - Storage (in-memory for stub)
    private var conversations: [String: Conversation] = [:]           // id -> conversation
    private var userConversationsIndex: [String: Set<String>] = [:]   // userId -> set of conversation ids
    private var messages: [String: [Message]] = [:]                   // conversationId -> messages (ascending by sentAt)

    // Live streams
    private var conversationStreams: [String: AsyncStream<[Conversation]>.Continuation] = [:]   // userId -> continuation
    private var messageStreams: [String: AsyncStream<[Message]>.Continuation] = [:]             // conversationId -> continuation

    // Cache directory for media (kept simple; adjust for real CloudKit)
    private let cacheDir: URL
    private let maxCacheBytes: Int64 = 80 * 1024 * 1024 // 80 MB

    // MARK: - Init

    init(container: CKContainer) {
        // For now we don’t use the container in the stub.
        self.cacheDir = CloudKitMessagingService.makeCacheDir()
    }

    convenience init(containerIdentifier: String) {
        self.init(container: CKContainer(identifier: containerIdentifier))
    }

    // MARK: - MessagingService conformance

    func getOrCreateDirectConversation(currentUserId: String, otherUserId: String, leadId: String?) async throws -> Conversation {
        // Try to find existing 1:1 conversation for the same pair and optional leadId
        if let conv = existingDirectConversation(between: currentUserId, and: otherUserId, leadId: leadId) {
            return conv
        }

        // Create new
        let id = UUID().uuidString
        var conv = Conversation(
            id: id,
            participantIds: [currentUserId, otherUserId],
            lastMessageText: "",
            lastMessageAt: Date(),
            unreadMap: [currentUserId: 0, otherUserId: 0],
            leadId: leadId,
            archivedMap: [:],
            deletedMap: [:]
        )
        conversations[id] = conv
        userConversationsIndex[currentUserId, default: []].insert(id)
        userConversationsIndex[otherUserId, default: []].insert(id)
        messages[id] = []

        // Notify streams for both users
        notifyConversationsChanged(for: currentUserId)
        notifyConversationsChanged(for: otherUserId)

        return conv
    }

    func fetchConversations(for userId: String) async throws -> [Conversation] {
        let ids = Array(userConversationsIndex[userId] ?? [])
        let convs = ids.compactMap { conversations[$0] }
        // Sort by lastMessageAt descending
        return convs.sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    func fetchMessages(conversationId: String, before: Date?, limit: Int) async throws -> [Message] {
        let all = messages[conversationId] ?? []
        let filtered: [Message]
        if let before {
            filtered = all.filter { $0.sentAt < before }
        } else {
            filtered = all
        }
        // Return last N messages (ascending by sentAt)
        return Array(filtered.suffix(limit))
    }

    func sendMessage(conversationId: String, text: String, senderId: String) async throws -> Message {
        let msg = Message(
            id: UUID().uuidString,
            conversationId: conversationId,
            senderId: senderId,
            text: text,
            sentAt: Date(),
            readBy: [senderId],
            mediaType: nil,
            mediaLocalURL: nil,
            mediaThumbnailURL: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaDuration: nil
        )
        try await appendMessage(msg)
        return msg
    }

    func sendMediaMessage(conversationId: String, senderId: String, fileURL: URL, kind: MediaKind, meta: MediaMeta?) async throws -> Message {
        // Copy media into our cache directory to ensure stable access
        let cachedURL = try copyToCache(src: fileURL, preferredName: "media-\(UUID().uuidString)")
        var thumbURL: URL? = nil
        if kind == .video {
            // For video, try to find a sibling thumb.jpg (as produced by ChatView helpers)
            let siblingThumb = cachedURL.deletingPathExtension().appendingPathExtension("thumb.jpg")
            if FileManager.default.fileExists(atPath: siblingThumb.path) {
                thumbURL = siblingThumb
            }
        }

        let msg = Message(
            id: UUID().uuidString,
            conversationId: conversationId,
            senderId: senderId,
            text: "",
            sentAt: Date(),
            readBy: [senderId],
            mediaType: kind.rawValue,
            mediaLocalURL: cachedURL,
            mediaThumbnailURL: thumbURL,
            mediaWidth: meta?.width,
            mediaHeight: meta?.height,
            mediaDuration: meta?.duration
        )
        try await appendMessage(msg)
        // Enforce cache budget after writes
        enforceCacheBudget()
        return msg
    }

    func markConversationRead(conversationId: String, userId: String) async throws {
        guard var conv = conversations[conversationId] else { return }
        conv.unreadMap[userId] = 0
        conversations[conversationId] = conv
        notifyConversationsChanged(forParticipantsOf: conv)
    }

    func totalUnreadCount(for userId: String) async throws -> Int {
        let ids = userConversationsIndex[userId] ?? []
        var total = 0
        for id in ids {
            if let conv = conversations[id] {
                total += max(0, conv.unreadMap[userId] ?? 0)
            }
        }
        return total
    }

    func observeConversations(for userId: String) -> AsyncStream<[Conversation]> {
        AsyncStream { continuation in
            conversationStreams[userId] = continuation
            // Immediately send current snapshot
            Task {
                let current = try? await fetchConversations(for: userId)
                continuation.yield(current ?? [])
            }
            continuation.onTermination = { [weak self] _ in
                self?.conversationStreams[userId] = nil
            }
        }
    }

    func observeMessages(conversationId: String) -> AsyncStream<[Message]> {
        AsyncStream { continuation in
            messageStreams[conversationId] = continuation
            // Immediately send current snapshot
            continuation.yield(messages[conversationId] ?? [])
            continuation.onTermination = { [weak self] _ in
                self?.messageStreams[conversationId] = nil
            }
        }
    }

    func ensureSubscriptions(for userId: String) async throws {
        // Stub: no-op in in-memory implementation
        _ = userId
    }

    func setArchived(conversationId: String, userId: String, archived: Bool) async throws {
        guard var conv = conversations[conversationId] else { return }
        conv.archivedMap[userId] = archived
        conversations[conversationId] = conv
        notifyConversationsChanged(forParticipantsOf: conv)
    }

    func softDelete(conversationId: String, userId: String) async throws {
        guard var conv = conversations[conversationId] else { return }
        conv.deletedMap[userId] = true
        conversations[conversationId] = conv
        notifyConversationsChanged(forParticipantsOf: conv)
    }

    // MARK: - Public helpers used by AppState

    func clearCachedMedia() {
        let fm = FileManager.default
        if fm.fileExists(atPath: cacheDir.path) {
            try? fm.removeItem(at: cacheDir)
        }
    }

    func enforceCacheBudget() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }

        var total: Int64 = 0
        var recs: [(url: URL, size: Int64, mdate: Date)] = []

        for url in items {
            do {
                let vals = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(vals.fileSize ?? 0)
                let mdate = vals.contentModificationDate ?? Date.distantPast
                total += size
                recs.append((url, size, mdate))
            } catch { }
        }

        guard total > maxCacheBytes else { return }
        recs.sort { $0.mdate < $1.mdate }

        var toFree = total - maxCacheBytes
        for r in recs {
            if toFree <= 0 { break }
            try? fm.removeItem(at: r.url)
            toFree -= r.size
        }
    }

    // MARK: - Private helpers

    private func existingDirectConversation(between a: String, and b: String, leadId: String?) -> Conversation? {
        let idsA = userConversationsIndex[a] ?? []
        for id in idsA {
            if let conv = conversations[id],
               Set(conv.participantIds) == Set([a, b]),
               conv.leadId == leadId {
                return conv
            }
        }
        return nil
    }

    private func appendMessage(_ msg: Message) async throws {
        var arr = messages[msg.conversationId] ?? []
        arr.append(msg)
        arr.sort { (lhs, rhs) -> Bool in
            if lhs.sentAt != rhs.sentAt { return lhs.sentAt < rhs.sentAt }
            return lhs.id < rhs.id
        }
        messages[msg.conversationId] = arr

        // Update conversation
        if var conv = conversations[msg.conversationId] {
            conv.lastMessageText = msg.mediaType == nil ? msg.text : (msg.mediaType == "photo" ? "Photo" : "Video")
            conv.lastMessageAt = msg.sentAt
            // Increase unread for other participants
            for uid in conv.participantIds where uid != msg.senderId {
                conv.unreadMap[uid] = max(0, (conv.unreadMap[uid] ?? 0)) + 1
            }
            // Sender has read it
            conv.unreadMap[msg.senderId] = 0
            conversations[msg.conversationId] = conv
            notifyConversationsChanged(forParticipantsOf: conv)
        }

        // Notify message stream
        if let cont = messageStreams[msg.conversationId] {
            cont.yield(arr)
        }
    }

    private func notifyConversationsChanged(for userId: String) {
        Task {
            let snapshot = try? await fetchConversations(for: userId)
            conversationStreams[userId]?.yield(snapshot ?? [])
        }
    }

    private func notifyConversationsChanged(forParticipantsOf conv: Conversation) {
        for uid in conv.participantIds {
            notifyConversationsChanged(for: uid)
        }
    }

    private static func makeCacheDir() -> URL {
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
        return cache
    }

    private func copyToCache(src: URL, preferredName: String) throws -> URL {
        let fm = FileManager.default
        let ext = src.pathExtension.isEmpty ? "bin" : src.pathExtension
        var dest = cacheDir.appendingPathComponent(preferredName).appendingPathExtension(ext)
        if fm.fileExists(atPath: dest.path) {
            dest = cacheDir.appendingPathComponent("\(preferredName)-\(UUID().uuidString)").appendingPathExtension(ext)
        }
        do {
            try fm.copyItem(at: src, to: dest)
        } catch {
            // If copy fails (e.g. security-scoped URL), fall back to re-writing bytes
            let data = try Data(contentsOf: src)
            try data.write(to: dest, options: [.atomic])
        }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dest.path)
        var rvs = URLResourceValues(); rvs.isExcludedFromBackup = true
        try? dest.setResourceValues(rvs)
        return dest
    }
}
