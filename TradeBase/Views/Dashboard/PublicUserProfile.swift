import Foundation

struct PublicUserProfile: Codable, Hashable {
    var name: String?
    var headline: String?
    var bio: String?
    var city: String?
    var avatarURL: URL?

    var mainSkills: [String]
    var subSkills: [String]

    // Certifications summary for simple list display
    var certificationsSummary: [String]

    // Compliance flags
    var hasPublicLiability: Bool
    var hasGuarantees: Bool

    init(
        name: String? = nil,
        headline: String? = nil,
        bio: String? = nil,
        city: String? = nil,
        avatarURL: URL? = nil,
        mainSkills: [String] = [],
        subSkills: [String] = [],
        certificationsSummary: [String] = [],
        hasPublicLiability: Bool = false,
        hasGuarantees: Bool = false
    ) {
        self.name = name
        self.headline = headline
        self.bio = bio
        self.city = city
        self.avatarURL = avatarURL
        self.mainSkills = mainSkills
        self.subSkills = subSkills
        self.certificationsSummary = certificationsSummary
        self.hasPublicLiability = hasPublicLiability
        self.hasGuarantees = hasGuarantees
    }
}
