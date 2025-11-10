import Foundation

struct UserProfile: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var headline: String
    var avatarURL: URL?
    var tradeTypes: [TradeType]
    var bio: String
    var certifications: [Certification]
    var reviews: [Review]
    var isPremium: Bool
    var skills: [String] = []

    // Customer-specific field (optional for backward compatibility)
    var city: String? = nil

    // New: globally unique username (optional)
    var username: String? = nil

    // Add this new field:
    var startYear: Int? = nil

    // NEW: Tradesperson compliance documents
    var publicLiabilityFileURL: URL? = nil
    var guaranteesFileURL: URL? = nil

    init(
        id: UUID = UUID(),
        name: String,
        headline: String,
        avatarURL: URL? = nil,
        tradeTypes: [TradeType],
        bio: String,
        certifications: [Certification],
        reviews: [Review],
        isPremium: Bool,
        skills: [String] = [],
        city: String? = nil,
        username: String? = nil,
        startYear: Int? = nil,
        publicLiabilityFileURL: URL? = nil,
        guaranteesFileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.headline = headline
        self.avatarURL = avatarURL
        self.tradeTypes = tradeTypes
        self.bio = bio
        self.certifications = certifications
        self.reviews = reviews
        self.isPremium = isPremium
        self.skills = skills
        self.city = city
        self.username = username
        self.startYear = startYear
        self.publicLiabilityFileURL = publicLiabilityFileURL
        self.guaranteesFileURL = guaranteesFileURL
    }
}

