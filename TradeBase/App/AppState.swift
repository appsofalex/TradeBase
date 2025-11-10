//
//  AppState.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import SwiftUI
import Observation
import EventKit
import GoogleSignIn
import AuthenticationServices
import UIKit
import CloudKit
import UserNotifications
import CoreLocation

// Back-compat: legacy code references UserRole; alias it to AppState.Role
enum UserRole: String, Codable { case customer, tradesperson }

@Observable
final class AppState {

    // MARK: - Core app-wide state (minimal surface to satisfy call sites)
    enum Role: String, Codable { case customer, tradesperson }

    // Auth
    enum AuthProvider: String, Codable { case apple, google, email, guest, x, none }
    var authProvider: AuthProvider = .none
    var authEmail: String? = nil
    var isAuthenticated: Bool = false

    // Gate used by CustomerHomeView/MyJobsView: only Apple/Google accounts can post jobs.
    var canCustomerPostJobs: Bool {
        switch authProvider {
        case .apple, .google:
            return true
        default:
            return false
        }
    }

    // Selected role for UI
    var selectedRole: Role? = nil

    // Marketplace filter used by LeadsView / FilterSheet
    var marketFilter: MarketFilter = MarketFilter()

    // Profile model used throughout the app
    struct UserProfile: Codable, Hashable {
        var id: UUID
        var name: String
        var headline: String
        var avatarURL: URL?
        var tradeTypes: [TradeType]
        var bio: String
        var certifications: [Certification]
        // Note: legacy projects stored reviews as strings; keep for compatibility
        var reviews: [String]
        var isPremium: Bool
        var skills: [String]
        var city: String?
        var username: String?
        // Optional start year to support yearsInIndustry extension
        var startYear: Int? = nil

        // Compliance documents (kept optional for compatibility with views referencing them)
        var publicLiabilityFileURL: URL? = nil
        var guaranteesFileURL: URL? = nil
    }

    static func defaultProfile() -> UserProfile {
        UserProfile(
            id: UUID(),
            name: "",
            headline: "",
            avatarURL: nil,
            tradeTypes: [],
            bio: "",
            certifications: [],
            reviews: [],
            isPremium: false,
            skills: [],
            city: nil,
            username: nil,
            startYear: nil,
            publicLiabilityFileURL: nil,
            guaranteesFileURL: nil
        )
    }

    var profile: UserProfile = AppState.defaultProfile()

    // Onboarding/setup flags used by load()
    var customerOnboardingCompleted: Bool = false
    var tradespersonOnboardingCompleted: Bool = false
    var customerSetupCompleted: Bool = false
    var tradespersonSetupCompleted: Bool = false

    // Legacy setup identity registries (persisted in UserDefaults)
    static let registeredCustomerAccountsKey = "registeredCustomerAccounts"
    static let registeredTradespersonAccountsKey = "registeredTradespersonAccounts"
    var registeredCustomerAccounts: Set<String> = []
    var registeredTradespersonAccounts: Set<String> = []

    // Used by deep link resume flow in TradeBaseApp
    var pendingJobResumeID: UUID? = nil

    // One-shot bypass flag to skip customer setup gate when needed
    var bypassCustomerSetupOnce: Bool = false

    // MyJobs navigation coordination (listened to by MyJobsView)
    var preferredMyJobsStatus: JobListingStatus? = nil
    var navigateToMyJobsSignal: Int = 0

    // Messaging placeholders referenced by views (lightweight so UI compiles)
    // Removed nested Conversation and Message in favor of shared models from MessagingModels.swift

    var conversations: [Conversation] = []
    var messagesCache: [String: [Message]] = [:]

    // Leads local state
    // Backing store as strings for compatibility; helpers bridge UUID<->String.
    var savedLeadIDs: [String] = []
    var hiddenLeadIDs: [String] = []

    // Expose marketplace leads to views
    var leads: [MarketplaceLead] = []

    // Community feed state used by CommunitiesView
    var posts: [CommunityPost] = []

    // App navigation animation hint used elsewhere
    enum NavDirection { case forward, back }
    var navigationDirection: NavDirection = .forward

    // MARK: - Unread messages badge

    // Used by DashboardView and CustomerHomeView to show a red dot on the bell icon.
    var unreadMessageCount: Int = 0

    // MARK: - Preferences (added)

    enum AppearanceMode: String, Codable, CaseIterable {
        case system, light, dark
    }

    // Backed by UserDefaults for persistence
    private let defaults = UserDefaults.standard
    private let notificationsEnabledKey = "prefs.notificationsEnabled"
    private let appearanceModeKey = "prefs.appearanceMode"

    var notificationsEnabled: Bool = false {
        didSet { defaults.set(notificationsEnabled, forKey: notificationsEnabledKey) }
    }

    var appearanceMode: AppearanceMode = .system {
        didSet { defaults.set(appearanceMode.rawValue, forKey: appearanceModeKey) }
    }

    // MARK: - Location filter for Leads (needed by LeadsListView and LeadsLocationPickerSheet)

    struct LeadsSearchLocation: Equatable, Hashable {
        var displayName: String
        var latitude: Double?
        var longitude: Double?
        var city: String?
        var postcode: String?

        var coordinate: CLLocationCoordinate2D? {
            guard let lat = latitude, let lon = longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    // Default to London so UI has a friendly initial value
    var leadsSearchLocation: LeadsSearchLocation = LeadsSearchLocation(
        displayName: "London",
        latitude: 51.5074,
        longitude: -0.1278,
        city: "London",
        postcode: nil
    )

    // Allow UI to prompt/fill location if needed. For now this is a no-op placeholder.
    func promptAndAutofillLeadsLocationIfNeeded() async {
        // In the future, you could request location permission and set leadsSearchLocation
        // based on the user's current city/postcode. Leaving as no-op keeps callers happy.
    }

    // MARK: - Services

    // CloudKit container used by various features
    let cloudKitContainer = CKContainer(identifier: "iCloud.com.AlexCo.TradeBase")

    // Concrete services
    let cloudProfileStore: CloudProfileStore
    let jobLeadService: JobLeadService

    // New: Messaging service used by Chat/Archived views
    let messagingService: MessagingService

    // New: Community service used by CommunitiesView and AppState+Community
    let communityService: CommunityService

    // Public profile store adapter exposed to UI
    actor PublicProfileStore {
        private let impl: CloudKitPublicProfileStore

        init(containerIdentifier: String) {
            self.impl = CloudKitPublicProfileStore(containerIdentifier: containerIdentifier)
        }

        // Map AppState.UserProfile (private) into public fields and upsert
        func upsert(from profile: AppState.UserProfile, identity: String) async throws {
            // For now, pass through to underlying store; it accepts UserProfile already
            try await impl.upsert(from: profile, identity: identity)
        }

        func updateAvatar(from fileURL: URL, identity: String) async throws {
            try await impl.updateAvatar(from: fileURL, identity: identity)
        }

        func fetch(identity: String) async throws -> PublicUserProfile {
            // Ask the underlying store for a PublicUserProfile; if none, synthesize a minimal one.
            if let publicProfile = try await impl.fetch(identity: identity) {
                return publicProfile
            } else {
                return PublicUserProfile(name: identity, headline: nil, bio: nil, city: nil, avatarURL: nil)
            }
        }
    }
    
    let publicProfileStore: PublicProfileStore? = PublicProfileStore(containerIdentifier: "iCloud.com.AlexCo.TradeBase")

    // MARK: - Messaging listeners (for RootView)

    private var messagingListenerTask: Task<Void, Never>? = nil

    func startMessagingListeners() {
        // Cancel any existing listener to avoid duplicates
        messagingListenerTask?.cancel()
        guard let me = currentAuthIdentity() else { return }
        messagingListenerTask = Task { [weak self] in
            guard let self else { return }
            // Ensure push subscriptions if backend supports it
            try? await self.messagingService.ensureSubscriptions(for: me)
            // Listen to conversations and keep unread badge up to date
            for await _ in self.messagingService.observeConversations(for: me) {
                await self.refreshUnreadCount()
            }
        }
    }

    func stopMessagingListeners() {
        messagingListenerTask?.cancel()
        messagingListenerTask = nil
    }

    // MARK: - Init

    init(
        cloudProfileStore: CloudProfileStore? = nil,
        jobLeadService: JobLeadService? = nil,
        messagingService: MessagingService? = nil,
        communityService: CommunityService? = nil
    ) {
        // Prefer provided implementations; otherwise build CloudKit-backed defaults.
        if let cps = cloudProfileStore {
            self.cloudProfileStore = cps
        } else {
            self.cloudProfileStore = CloudKitProfileStore(containerIdentifier: "iCloud.com.AlexCo.TradeBase")
        }

        if let jls = jobLeadService {
            self.jobLeadService = jls
        } else {
            self.jobLeadService = CloudKitJobLeadServiceAdapter(containerIdentifier: "iCloud.com.AlexCo.TradeBase")
        }

        if let ms = messagingService {
            self.messagingService = ms
        } else {
            // Use the CloudKit-backed messaging service (production container)
            self.messagingService = CloudKitMessagingServiceCK(containerIdentifier: "iCloud.com.AlexCo.TradeBase")
        }

        if let cs = communityService {
            self.communityService = cs
        } else {
            // Default to CloudKit-backed community service
            self.communityService = CloudKitCommunityService(containerIdentifier: "iCloud.com.AlexCo.TradeBase")
        }

        // Load legacy setup registries
        let cust = (UserDefaults.standard.array(forKey: Self.registeredCustomerAccountsKey) as? [String]) ?? []
        let trad = (UserDefaults.standard.array(forKey: Self.registeredTradespersonAccountsKey) as? [String]) ?? []
        self.registeredCustomerAccounts = Set(cust)
        self.registeredTradespersonAccounts = Set(trad)

        // Ensure identity-scoped local profile is present for current identity
        loadPersistedProfile()

        // Seed preferences from UserDefaults
        if defaults.object(forKey: notificationsEnabledKey) != nil {
            self.notificationsEnabled = defaults.bool(forKey: notificationsEnabledKey)
        } else {
            self.notificationsEnabled = false
        }
        if let raw = defaults.string(forKey: appearanceModeKey),
           let mode = AppearanceMode(rawValue: raw) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }
    }

    // MARK: - Identity

    func currentAuthIdentity() -> String? {
        switch authProvider {
        case .apple:
            if let s = UserDefaults.standard.string(forKey: "apple_user_id"), !s.isEmpty { return "apple:\(s)" }
        case .google:
            if let s = UserDefaults.standard.string(forKey: "google_user_id"), !s.isEmpty { return "google:\(s)" }
        case .email:
            if let email = authEmail, !email.isEmpty { return "email:\(email.lowercased())" }
        case .guest, .x, .none:
            break
        }
        return nil
    }

    // MARK: - Lifecycle/load

    func load() async {
        await refreshProfileFromCloud()
        await refreshLeads()

        if let id = currentAuthIdentity() {
            if let flags = try? await cloudProfileStore.fetchOnboardingFlags(identity: id) {
                await MainActor.run {
                    self.customerOnboardingCompleted = flags.customerOnboardingCompleted
                    self.tradespersonOnboardingCompleted = flags.tradespersonOnboardingCompleted
                    self.customerSetupCompleted = flags.customerSetupCompleted
                    self.tradespersonSetupCompleted = flags.tradespersonSetupCompleted
                }
            }
        }

        await MainActor.run {
            self.loadPersistedProfile()
        }
    }

    // MARK: - Profile sync

    func refreshProfileFromCloud() async {
        guard let id = currentAuthIdentity() else { return }
        do {
            if let remote = try await cloudProfileStore.fetchUserProfile(identity: id) {
                await MainActor.run {
                    self.profile = UserProfile(
                        id: remote.id,
                        name: remote.name,
                        headline: remote.headline,
                        avatarURL: remote.avatarURL,
                        tradeTypes: remote.tradeTypes,
                        bio: remote.bio,
                        certifications: remote.certifications,
                        reviews: remote.reviews,
                        isPremium: remote.isPremium,
                        skills: remote.skills,
                        city: remote.city,
                        username: remote.username,
                        startYear: nil,
                        publicLiabilityFileURL: nil,
                        guaranteesFileURL: nil
                    )
                }
                savePersistedProfile()
            }
        } catch {
            // Silent failure is acceptable for background sync; keep app running
        }
    }

    // MARK: - Leads

    func refreshLeads() async {
        // Ensure CK subscription and enforce profile asset cache budget
        try? await jobLeadService.ensureSubscription()
        try? await cloudProfileStore.enforceCacheBudget()

        // Fetch latest marketplace leads and publish to UI
        do {
            let latest = try await jobLeadService.latest()
            await MainActor.run {
                self.leads = latest
            }
        } catch {
            // Keep previous leads on failure
        }
    }

    // Convenience to match older call sites that expected ensureLeadsSubscription on AppState
    func ensureLeadsSubscription() async throws {
        try await jobLeadService.ensureSubscription()
    }

    // Saved/hidden helpers used by views

    func isLeadSaved(_ id: UUID) -> Bool {
        let key = id.uuidString.lowercased()
        return savedLeadIDs.contains { $0.lowercased() == key }
    }

    func toggleSave(lead: MarketplaceLead) {
        let key = lead.id.uuidString.lowercased()
        if let idx = savedLeadIDs.firstIndex(where: { $0.lowercased() == key }) {
            savedLeadIDs.remove(at: idx)
        } else {
            savedLeadIDs.append(key)
        }
    }

    func hideLead(id: UUID) {
        let key = id.uuidString.lowercased()
        if !hiddenLeadIDs.contains(where: { $0.lowercased() == key }) {
            hiddenLeadIDs.append(key)
        }
    }

    // New: unhide helpers used by HiddenLeadsView toolbar and rows
    func unhideLead(id: UUID) {
        let key = id.uuidString.lowercased()
        if let idx = hiddenLeadIDs.firstIndex(where: { $0.lowercased() == key }) {
            hiddenLeadIDs.remove(at: idx)
        }
    }

    func unhideAllLeads() {
        hiddenLeadIDs.removeAll()
    }

    // MARK: - Local profile persistence (identity-scoped)

    private func profileFileURL(for identity: String?) -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) { try? fm.createDirectory(at: appDir, withIntermediateDirectories: true) }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)
        let name = (identity?.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression) ?? "guest")
        return appDir.appendingPathComponent("Profile_\(name).json")
    }

    func loadPersistedProfile() {
        let url = profileFileURL(for: currentAuthIdentity())
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
            self.profile = decoded
        } catch {
            // Ignore corrupt file and keep in-memory profile
        }
    }

    private func savePersistedProfile() {
        let url = profileFileURL(for: currentAuthIdentity())
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: url, options: [.atomic])
        } catch {
            // ignore
        }
    }

    // Convenience used by extensions (e.g., Setup, Certifications) to persist local profile changes.
    func saveProfile() {
        savePersistedProfile()
    }

    func deleteLocalProfile() {
        let url = profileFileURL(for: currentAuthIdentity())
        try? FileManager.default.removeItem(at: url)
    }

    func clearScopedDefaults() {
        UserDefaults.standard.removeObject(forKey: "apple_user_id")
        UserDefaults.standard.removeObject(forKey: "google_user_id")
    }

    // MARK: - Avatar update (used by Settings/Profile views)

    func updateAvatar(with data: Data) async {
        // 1) Write to an app-private file for immediate local display
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        let avatarsDir = appDir.appendingPathComponent("Avatars", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) {
            try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: avatarsDir.path) {
            try? fm.createDirectory(at: avatarsDir, withIntermediateDirectories: true)
        }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: avatarsDir.path)

        let filename = "avatar-\(Int(Date().timeIntervalSince1970)).jpg"
        var fileURL = avatarsDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL, options: [.atomic])
            var rvs = URLResourceValues()
            rvs.isExcludedFromBackup = true
            try? fileURL.setResourceValues(rvs)
        } catch {
            // If write fails, bail out silently to avoid crashing UI
            return
        }

        // 2) Update in-memory profile and persist locally
        await MainActor.run {
            self.profile.avatarURL = fileURL
            self.savePersistedProfile()
        }

        // 3) Best-effort remote uploads if authenticated
        if let identity = currentAuthIdentity() {
            // Private (CloudKit) avatar asset
            if let ckStore = cloudProfileStore as? CloudKitProfileStore {
                try? await ckStore.updateAvatarAsset(from: fileURL, identity: identity)
            }
            // Public profile mirror (so others can see it)
            try? await publicProfileStore?.updateAvatar(from: fileURL, identity: identity)

            // 4) Optionally refresh from cloud to pick up any remote URL or cache changes
            await refreshProfileFromCloud()
        }
    }

    // MARK: - App badge (placeholder to satisfy references)

    func updateAppIconBadge() {
        // No-op background implementation
    }

    // MARK: - Sign out

    @MainActor
    func signOut() {
        self.isAuthenticated = false
        self.authProvider = .none
        self.authEmail = nil
        self.profile = AppState.defaultProfile()
        self.unreadMessageCount = 0
    }

    // MARK: - Guest session

    @MainActor
    func continueAsGuest() async {
        // Enter guest mode: no persistent identity; profile persists under "guest"
        self.isAuthenticated = true
        self.authProvider = .guest
        self.authEmail = nil
        // Keep existing local profile if any guest profile exists; otherwise default
        if currentAuthIdentity() == nil {
            // Save a fresh guest profile file so subsequent launches can restore minimal state
            self.profile = AppState.defaultProfile()
            savePersistedProfile()
        }
        // Hydrate any non-identity-scoped state (e.g., leads)
        await load()
        self.unreadMessageCount = 0
    }

    // MARK: - Unread count refresh used by ChatView and headers

    func refreshUnreadCount() async {
        guard let me = currentAuthIdentity() else {
            await MainActor.run { self.unreadMessageCount = 0 }
            return
        }
        do {
            let total = try await messagingService.totalUnreadCount(for: me)
            await MainActor.run { self.unreadMessageCount = max(0, total) }
        } catch {
            // On failure, leave previous value; optionally set to 0
            // await MainActor.run { self.unreadMessageCount = 0 }
        }
    }

    // MARK: - Account deletion (used by Settings views)

    func deleteAccount() async throws {
        // Capture identity if present
        let identity = currentAuthIdentity()

        // Attempt remote cleanup best-effort, capture first error
        var firstError: Error?

        if let id = identity {
            // Remove private avatar asset (optional)
            do {
                try await cloudProfileStore.removeAvatarAsset(identity: id)
            } catch {
                if firstError == nil { firstError = error }
            }

            // Delete user profile record
            do {
                try await cloudProfileStore.deleteUserProfile(identity: id)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        // Local cleanup regardless of remote outcome
        deleteLocalProfile()
        clearScopedDefaults()

        // Reset in-memory auth/profile state
        await MainActor.run {
            self.signOut()
        }

        // If we encountered a remote error for an identified account, surface it
        if let err = firstError, identity != nil {
            throw err
        }
    }

    // MARK: - Messaging convenience used by LeadDetailView

    func openOrCreateConversation(with otherUserId: String, leadId: String?) async throws -> Conversation {
        guard let me = currentAuthIdentity(), !otherUserId.isEmpty else {
            throw NSError(domain: "AppState", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let convo: Conversation = try await messagingService.getOrCreateDirectConversation(
            currentUserId: me,
            otherUserId: otherUserId,
            leadId: leadId
        )
        return convo
    }

    // MARK: - Notifications permission helper (used by CustomerHomeView)
    func requestNotificationPermissionsIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        case .denied, .authorized, .provisional, .ephemeral:
            // No-op here; caller can decide how to handle denied/provisional if needed.
            break
        @unknown default:
            break
        }
    }
} // <-- Close AppState here

// MARK: - Protocols and default service stubs

protocol JobLeadService {
    func latest() async throws -> [MarketplaceLead]
    func upsert(from listing: JobListing, posterIdentity: String?, posterAppID: UUID, photoFileURLs: [URL]) async throws
    func ensureSubscription() async throws
    func updateStatus(recordName: String, to newStatus: JobListingStatus) async throws
}

struct DefaultJobLeadService: JobLeadService {
    func latest() async throws -> [MarketplaceLead] { [] }
    func upsert(from listing: JobListing, posterIdentity: String?, posterAppID: UUID, photoFileURLs: [URL]) async throws { }
    func ensureSubscription() async throws { }
    func updateStatus(recordName: String, to newStatus: JobListingStatus) async throws { }
}

final class CloudKitJobLeadServiceAdapter: JobLeadService {
    private let impl: CloudKitJobLeadService
    init(containerIdentifier: String) {
        self.impl = CloudKitJobLeadService(containerIdentifier: containerIdentifier)
    }
    func latest() async throws -> [MarketplaceLead] { try await impl.latest() }
    func upsert(from listing: JobListing, posterIdentity: String?, posterAppID: UUID, photoFileURLs: [URL]) async throws {
        try await impl.upsert(from: listing, posterIdentity: posterIdentity, posterAppID: posterAppID, photoFileURLs: photoFileURLs)
    }
    func ensureSubscription() async throws { try await impl.ensureSubscription() }
    func updateStatus(recordName: String, to newStatus: JobListingStatus) async throws {
        try await impl.updateStatus(recordName: recordName, to: newStatus)
    }
}

// Extend protocol to include onboarding flags and make enforceCacheBudget async throws.
protocol CloudProfileStore {
    func fetchUserProfile(identity: String) async throws -> AppState.UserProfile?
    func fetchCertifications(identity: String) async throws -> [Certification]
    func upsertCertification(_ cert: Certification, fileURL: URL?, identity: String) async throws
    func deleteCertification(id: UUID) async throws
    func removeAvatarAsset(identity: String) async throws
    func deleteUserProfile(identity: String) async throws

    func fetchOnboardingFlags(identity: String) async throws -> CloudKitProfileStore.OnboardingFlags?

    func enforceCacheBudget() async throws

    // NEW: resolve a cloud identity from a posterAppID (if supported by backend)
    func identity(forAppID appID: UUID) async throws -> String?
}

actor DefaultCloudProfileStore: CloudProfileStore {
    func fetchUserProfile(identity: String) async throws -> AppState.UserProfile? { nil }
    func fetchCertifications(identity: String) async throws -> [Certification] { [] }
    func upsertCertification(_ cert: Certification, fileURL: URL?, identity: String) async throws { }
    func deleteCertification(id: UUID) async throws { }
    func removeAvatarAsset(identity: String) async throws { }
    func deleteUserProfile(identity: String) async throws { }
    func fetchOnboardingFlags(identity: String) async throws -> CloudKitProfileStore.OnboardingFlags? { nil }
    func enforceCacheBudget() async throws { }

    // Default no-op: backends that don't support appID->identity mapping return nil
    func identity(forAppID appID: UUID) async throws -> String? { nil }
}
