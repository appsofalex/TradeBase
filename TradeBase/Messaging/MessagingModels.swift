import Foundation

struct Conversation: Identifiable, Hashable, Codable {
    var id: String
    var participantIds: [String]
    var lastMessageText: String
    var lastMessageAt: Date
    var unreadMap: [String: Int]
    var leadId: String?

    // New: per-user archive/delete flags (soft state)
    var archivedMap: [String: Bool]
    var deletedMap: [String: Bool]

    init(
        id: String,
        participantIds: [String],
        lastMessageText: String = "",
        lastMessageAt: Date = .distantPast,
        unreadMap: [String: Int] = [:],
        leadId: String? = nil,
        archivedMap: [String: Bool] = [:],
        deletedMap: [String: Bool] = [:]
    ) {
        self.id = id
        self.participantIds = participantIds
        self.lastMessageText = lastMessageText
        self.lastMessageAt = lastMessageAt
        self.unreadMap = unreadMap
        self.leadId = leadId
        self.archivedMap = archivedMap
        self.deletedMap = deletedMap
    }

    func unreadCount(for userId: String) -> Int {
        unreadMap[userId] ?? 0
    }

    func isArchived(for userId: String) -> Bool {
        archivedMap[userId] ?? false
    }

    func isDeleted(for userId: String) -> Bool {
        deletedMap[userId] ?? false
    }
}

struct Message: Identifiable, Hashable, Codable {
    var id: String
    var conversationId: String
    var senderId: String
    var text: String
    var sentAt: Date
    var readBy: [String]

    // Optional single media attachment (v1)
    var mediaType: String?          // "photo" | "video"
    var mediaLocalURL: URL?         // local cached file for image/video
    var mediaThumbnailURL: URL?     // local cached thumbnail (video; optional for images)
    var mediaWidth: Double?
    var mediaHeight: Double?
    var mediaDuration: Double?      // seconds, for video

    init(
        id: String,
        conversationId: String,
        senderId: String,
        text: String,
        sentAt: Date,
        readBy: [String] = [],
        mediaType: String? = nil,
        mediaLocalURL: URL? = nil,
        mediaThumbnailURL: URL? = nil,
        mediaWidth: Double? = nil,
        mediaHeight: Double? = nil,
        mediaDuration: Double? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.text = text
        self.sentAt = sentAt
        self.readBy = readBy
        self.mediaType = mediaType
        self.mediaLocalURL = mediaLocalURL
        self.mediaThumbnailURL = mediaThumbnailURL
        self.mediaWidth = mediaWidth
        self.mediaHeight = mediaHeight
        self.mediaDuration = mediaDuration
    }
}

