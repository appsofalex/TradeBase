import Foundation

protocol MessagingService {
    // Conversations
    func getOrCreateDirectConversation(currentUserId: String, otherUserId: String, leadId: String?) async throws -> Conversation
    func fetchConversations(for userId: String) async throws -> [Conversation]

    // Messages
    func fetchMessages(conversationId: String, before: Date?, limit: Int) async throws -> [Message]
    func sendMessage(conversationId: String, text: String, senderId: String) async throws -> Message

    // Media messages (new)
    func sendMediaMessage(conversationId: String, senderId: String, fileURL: URL, kind: MediaKind, meta: MediaMeta?) async throws -> Message

    // Read/unread
    func markConversationRead(conversationId: String, userId: String) async throws
    func totalUnreadCount(for userId: String) async throws -> Int

    // Live updates
    func observeConversations(for userId: String) -> AsyncStream<[Conversation]>
    func observeMessages(conversationId: String) -> AsyncStream<[Message]>

    // Subscriptions (push)
    func ensureSubscriptions(for userId: String) async throws

    // New: per-user archive/delete (soft)
    func setArchived(conversationId: String, userId: String, archived: Bool) async throws
    func softDelete(conversationId: String, userId: String) async throws
}

// Shared helper types for media API
enum MediaKind: String, Codable {
    case photo
    case video
}

struct MediaMeta: Codable {
    var width: Double?
    var height: Double?
    var duration: Double?
    init(width: Double? = nil, height: Double? = nil, duration: Double? = nil) {
        self.width = width
        self.height = height
        self.duration = duration
    }
}

