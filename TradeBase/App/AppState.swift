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
import CoreLocation

// Back-compat: legacy code references UserRole; alias it to AppState.Role
enum UserRole: String, Codable { case customer, tradesperson }

@Observable
final class AppState {

    // MARK: - Core app-wide state (minimal surface to satisfy call sites)
    enum Role: String, Codable { case customer, tradesperson }

    // Auth
    enum AuthProvider: String, Codable { case apple, google, email, guest, x, none }

    // Backed by persistence (see keys below)
    var authProvider: AuthProvider = .none {
        didSet {
            defaults.set(authProvider.rawValue, forKey: authProviderKey)
        }
    }
    var authEmail: String? = nil {
        didSet {
            defaults.set(authEmail, forKey: authEmailKey)
        }
    }

    // When auth flips to false, force role to nil so RootView shows RolePickerView.
    var isAuthenticated: Bool = false {
        didSet {
            defaults.set(isAuthenticated, forKey: isAuthenticatedKey)
            if isAuthenticated == false {
                // Ensure we never route into unauthenticated onboarding for a pre-selected role
                selectedRole = nil
            }
        }
    }

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
    var selectedRole: Role? = nil {
        didSet {
            if let r = selectedRole {
                defaults.set(r.rawValue, forKey: selectedRoleKey)
            } else {
                defaults.removeObject(forKey: selectedRoleKey)
            }
        }
    }

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
    // Persist these locally so the onboarding is only shown once per install.
    var customerOnboardingCompleted: Bool = false {
        didSet { defaults.set(customerOnboardingCompleted, forKey: customerOnboardingCompletedKey) }
    }
    var tradespersonOnboardingCompleted: Bool = false {
        didSet { defaults.set(tradespersonOnboardingCompleted, forKey: tradespersonOnboardingCompletedKey) }
    }
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
    var conversations: [Conversation] = []
    var messagesCache: [String: [Message]] = [:]

    // Leads local state
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

    // New: keys for onboarding-completed persistence
    private let customerOnboardingCompletedKey = "onboarding.customer.completed"
    private let tradespersonOnboardingCompletedKey = "onboarding.tradesperson.completed"

    // New: keys for auth/session persistence
    private let authProviderKey = "auth.provider"
    private let authEmailKey = "auth.email"
    private let isAuthenticatedKey = "auth.isAuthenticated"
    private let selectedRoleKey = "auth.selectedRole"

    var notificationsEnabled: Bool = false {
        didSet { defaults.set(notificationsEnabled, forKey: notificationsEnabledKey) }
    }

    var appearanceMode: AppearanceMode = .system {
        didSet { defaults.set(appearanceMode.rawValue, forKey: appearanceModeKey) }
    }

    // MARK: - Location filter for Leads

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

    func promptAndAutofillLeadsLocationIfNeeded() async {
        // Placeholder: no-op
    }

    // MARK: - Services

    let cloudKitContainer = CKContainer(identifier: "iCloud.com.AlexCo.TradeBase")

    let cloudProfileStore: CloudProfileStore
    let jobLeadService: JobLeadService
    let messagingService: MessagingService
    let communityService: CommunityService

    // Public profile store adapter exposed to UI
    actor PublicProfileStore {
        private let impl: CloudKitPublicProfileStore

        init(containerIdentifier: String) {
            self.impl = CloudKitPublicProfileStore(containerIdentifier: containerIdentifier)
        }

        func upsert(from profile: AppState.UserProfile, identity: String) async throws {
            try await impl.upsert(from: profile, identity: identity)
        }

        func updateAvatar(from fileURL: URL, identity: String) async throws {
            try await impl.updateAvatar(from: fileURL, identity: identity)
        }

        func fetch(identity: String) async throws -> PublicUserProfile {
            if let publicProfile = try await impl.fetch(identity: identity) {
                return publicProfile
            } else {
                return PublicUserProfile(name: identity, headline: nil, bio: nil, city: nil, avatarURL: nil)
            }
        }

        // NEW: Forward compliance document operations to CloudKitPublicProfileStore
        func updatePublicLiability(from fileURL: URL, identity: String) async throws {
            try await impl.updatePublicLiability(from: fileURL, identity: identity)
        }

        func clearPublicLiability(identity: String) async throws {
            try await impl.clearPublicLiability(identity: identity)
        }

        func updateGuarantees(from fileURL: URL, identity: String) async throws {
            try await impl.updateGuarantees(from: fileURL, identity: identity)
        }

        func clearGuarantees(identity: String) async throws {
            try await impl.clearGuarantees(identity: identity)
        }
    }
    
    let publicProfileStore: PublicProfileStore? = PublicProfileStore(containerIdentifier: "iCloud.com.AlexCo.TradeBase")

    // MARK: - Messaging listeners (for RootView)

    private var messagingListenerTask: Task<Void, Never>? = nil

    func startMessagingListeners() {
        messagingListenerTask?.cancel()
        guard let me = currentAuthIdentity() else { return }
        messagingListenerTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.messagingService.ensureSubscriptions(for: me)
                for try await _ in self.messagingService.observeConversations(for: me) {
                    await self.refreshUnreadCount()
                }
            } catch {
                // Swallow stream/observer failures; listeners will be restarted on next app event
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
        self.cloudProfileStore = cloudProfileStore ?? CloudKitProfileStore(containerIdentifier: "iCloud.com.AlexCo.TradeBase")
        self.jobLeadService = jobLeadService ?? CloudKitJobLeadServiceAdapter(containerIdentifier: "iCloud.com.AlexCo.TradeBase")
        self.messagingService = messagingService ?? CloudKitMessagingServiceCK(containerIdentifier: "iCloud.com.AlexCo.TradeBase")
        self.communityService = communityService ?? CloudKitCommunityService(containerIdentifier: "iCloud.com.AlexCo.TradeBase")

        // Load legacy setup registries
        let cust = (UserDefaults.standard.array(forKey: Self.registeredCustomerAccountsKey) as? [String]) ?? []
        let trad = (UserDefaults.standard.array(forKey: Self.registeredTradespersonAccountsKey) as? [String]) ?? []
        self.registeredCustomerAccounts = Set(cust)
        self.registeredTradespersonAccounts = Set(trad)

        // Restore persisted auth/session state first so RootView routes correctly on cold launch.
        restoreAuthStateFromDefaults()

        // Ensure identity-scoped local profile is present for current identity
        loadPersistedProfile()
        // Load identity-scoped scheduled leads
        loadScheduledLeadIDs()

        // Preferences
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

        // Onboarding-completed flags
        if defaults.object(forKey: customerOnboardingCompletedKey) != nil {
            self.customerOnboardingCompleted = defaults.bool(forKey: customerOnboardingCompletedKey)
        } else {
            self.customerOnboardingCompleted = false
        }
        if defaults.object(forKey: tradespersonOnboardingCompletedKey) != nil {
            self.tradespersonOnboardingCompleted = defaults.bool(forKey: tradespersonOnboardingCompletedKey)
        } else {
            self.tradespersonOnboardingCompleted = false
        }

        // Attempt silent provider session restoration (must be main-thread safe for Google on iOS 18).
        Task { [weak self] in
            await self?.attemptSilentProviderRestoration()
        }
    }

    // MARK: - Auth restoration

    private func restoreAuthStateFromDefaults() {
        if let raw = defaults.string(forKey: authProviderKey),
           let prov = AuthProvider(rawValue: raw) {
            self.authProvider = prov
        } else {
            self.authProvider = .none
        }
        self.authEmail = defaults.string(forKey: authEmailKey)

        if let rawRole = defaults.string(forKey: selectedRoleKey),
           let role = Role(rawValue: rawRole) {
            self.selectedRole = role
        } else {
            self.selectedRole = nil
        }

        let hasIdentity: Bool = {
            switch authProvider {
            case .apple:
                if let s = UserDefaults.standard.string(forKey: "apple_user_id"), !s.isEmpty { return true }
                return false
            case .google:
                if let s = UserDefaults.standard.string(forKey: "google_user_id"), !s.isEmpty { return true }
                return false
            case .email:
                if let email = authEmail, !email.isEmpty { return true }
                return false
            case .guest:
                return true
            case .x, .none:
                return false
            }
        }()
        if defaults.object(forKey: isAuthenticatedKey) != nil {
            let stored = defaults.bool(forKey: isAuthenticatedKey)
            self.isAuthenticated = stored && hasIdentity
        } else {
            self.isAuthenticated = hasIdentity
        }
    }

    // Google SDK requires main-thread entry on older iOS; run this on MainActor.
    @MainActor
    private func restoreGoogleSessionOnMainActor() async throws {
        try await GIDSignIn.sharedInstance.restorePreviousSignIn()
    }

    private func attemptSilentProviderRestoration() async {
        switch authProvider {
        case .google:
            do {
                try await restoreGoogleSessionOnMainActor()
            } catch {
                // Best-effort; keep optimistic state
            }
        case .apple:
            if let userID = UserDefaults.standard.string(forKey: "apple_user_id"), !userID.isEmpty {
                let provider = ASAuthorizationAppleIDProvider()
                do {
                    let state = try await provider.credentialState(forUserID: userID)
                    if state != .authorized {
                        await MainActor.run { self.signOut() }
                    }
                } catch { /* ignore */ }
            }
        case .email, .guest, .x, .none:
            break
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
        // Load local profile first so UI shows exactly what the user last saved.
        await MainActor.run {
            self.loadPersistedProfile()
            self.loadScheduledLeadIDs()
        }

        // Then refresh from cloud in the background; if remote exists, it will overwrite and be re-saved.
        await refreshProfileFromCloud()
        await refreshLeads()

        if let id = currentAuthIdentity() {
            if let flags = try? await cloudProfileStore.fetchOnboardingFlags(identity: id) {
                await MainActor.run {
                    self.customerOnboardingCompleted = self.customerOnboardingCompleted || flags.customerOnboardingCompleted
                    self.tradespersonOnboardingCompleted = self.tradespersonOnboardingCompleted || flags.tradespersonOnboardingCompleted
                    self.customerSetupCompleted = self.customerSetupCompleted || flags.customerSetupCompleted
                    self.tradespersonSetupCompleted = self.tradespersonSetupCompleted || flags.tradespersonSetupCompleted
                }
            }
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
            // Silent failure is acceptable for background sync
        }
    }

    // MARK: - Leads

    func refreshLeads() async {
        try? await jobLeadService.ensureSubscription()
        try? await cloudProfileStore.enforceCacheBudget()

        do {
            let latest = try await jobLeadService.latest()
            await MainActor.run {
                self.leads = latest
            }
        } catch {
            // Keep previous leads on failure
        }
    }

    func ensureLeadsSubscription() async throws {
        try await jobLeadService.ensureSubscription()
    }

    // Saved/hidden helpers

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

    func unhideLead(id: UUID) {
        let key = id.uuidString.lowercased()
        if let idx = hiddenLeadIDs.firstIndex(where: { $0.lowercased() == key }) {
            hiddenLeadIDs.remove(at: idx)
        }
    }

    func unhideAllLeads() {
        hiddenLeadIDs.removeAll()
    }

    // MARK: - Scheduled leads (Your Schedule uses the exact lead tiles)

    // In-memory cache of scheduled lead IDs (identity-scoped)
    private(set) var scheduledLeadIDs: Set<UUID> = []

    // Add a lead to the schedule (de-duplicated)
    func addToSchedule(lead: MarketplaceLead) {
        scheduledLeadIDs.insert(lead.id)
        saveScheduledLeadIDs()
    }

    func removeFromSchedule(id: UUID) {
        scheduledLeadIDs.remove(id)
        saveScheduledLeadIDs()
    }

    func isInSchedule(_ id: UUID) -> Bool {
        scheduledLeadIDs.contains(id)
    }

    // Return actual MarketplaceLead objects for the scheduled IDs
    func scheduledLeads(from allLeads: [MarketplaceLead]) -> [MarketplaceLead] {
        let set = scheduledLeadIDs
        return allLeads.filter { set.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
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

    // Identity-scoped scheduled IDs file
    private func scheduledIDsFileURL(for identity: String?) -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) { try? fm.createDirectory(at: appDir, withIntermediateDirectories: true) }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)
        let name = (identity?.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression) ?? "guest")
        return appDir.appendingPathComponent("ScheduledLeads_\(name).json")
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
            // Ignore corrupt file
        }
    }

    private func savePersistedProfile() {
        let url = profileFileURL(for: currentAuthIdentity())
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: url, options: [.atomic])
        } catch { }
    }

    func saveProfile() {
        savePersistedProfile()
    }

    // Scheduled IDs persistence

    private func loadScheduledLeadIDs() {
        let url = scheduledIDsFileURL(for: currentAuthIdentity())
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            scheduledLeadIDs = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let ids = try JSONDecoder().decode([UUID].self, from: data)
            scheduledLeadIDs = Set(ids)
        } catch {
            scheduledLeadIDs = []
        }
    }

    private func saveScheduledLeadIDs() {
        let url = scheduledIDsFileURL(for: currentAuthIdentity())
        do {
            let ids = Array(scheduledLeadIDs)
            let data = try JSONEncoder().encode(ids)
            try data.write(to: url, options: [.atomic])
        } catch { }
    }

    func deleteLocalProfile() {
        let url = profileFileURL(for: currentAuthIdentity())
        try? FileManager.default.removeItem(at: url)
    }

    func clearScopedDefaults() {
        UserDefaults.standard.removeObject(forKey: "apple_user_id")
        UserDefaults.standard.removeObject(forKey: "google_user_id")
    }

    // MARK: - Avatar update

    func updateAvatar(with data: Data) async {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        let avatarsDir = appDir.appendingPathComponent("Avatars", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) { try? fm.createDirectory(at: appDir, withIntermediateDirectories: true) }
        if !fm.fileExists(atPath: avatarsDir.path) { try? fm.createDirectory(at: avatarsDir, withIntermediateDirectories: true) }
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
            return
        }

        await MainActor.run {
            self.profile.avatarURL = fileURL
            self.savePersistedProfile()
        }

        if let identity = currentAuthIdentity() {
            if let ckStore = cloudProfileStore as? CloudKitProfileStore {
                try? await ckStore.updateAvatarAsset(from: fileURL, identity: identity)
            }
            try? await cloudProfileStore.saveProfile(self.profile, identity: identity)
            try? await publicProfileStore?.updateAvatar(from: fileURL, identity: identity)
            await refreshProfileFromCloud()
        }
    }

    // MARK: - App badge

    func updateAppIconBadge() { }

    // MARK: - Sign out

    private func flushProfileEditsBeforeSignOut() async {
        savePersistedProfile()
        if let id = currentAuthIdentity() {
            do { try await cloudProfileStore.saveProfile(self.profile, identity: id) } catch { }
        }
    }

    @MainActor
    func signOut() {
        self.stopMessagingListeners()
        Task { await self.flushProfileEditsBeforeSignOut() }

        self.isAuthenticated = false
        self.authProvider = .none
        self.authEmail = nil

        self.selectedRole = nil
        self.pendingJobResumeID = nil
        self.preferredMyJobsStatus = nil
        self.navigateToMyJobsSignal = 0
        self.bypassCustomerSetupOnce = false

        self.customerSetupCompleted = false
        self.tradespersonSetupCompleted = false

        self.profile = AppState.defaultProfile()
        self.unreadMessageCount = 0
        self.scheduledLeadIDs = []
    }

    // MARK: - Guest session

    @MainActor
    func continueAsGuest() async {
        self.isAuthenticated = true
        self.authProvider = .guest
        self.authEmail = nil
        if currentAuthIdentity() == nil {
            self.profile = AppState.defaultProfile()
            savePersistedProfile()
        }
        await load()
        self.unreadMessageCount = 0
    }

    // MARK: - Unread count refresh

    func refreshUnreadCount() async {
        guard let me = currentAuthIdentity() else {
            await MainActor.run { self.unreadMessageCount = 0 }
            return
        }
        do {
            let total = try await messagingService.totalUnreadCount(for: me)
            await MainActor.run { self.unreadMessageCount = max(0, total) }
        } catch {
            // Keep previous value
        }
    }

    // MARK: - Account deletion

    func deleteAccount() async throws {
        let identity = currentAuthIdentity()
        var firstError: Error?

        if let id = identity {
            do { try await cloudProfileStore.removeAvatarAsset(identity: id) } catch { if firstError == nil { firstError = error } }
            do { try await cloudProfileStore.deleteUserProfile(identity: id) } catch { if firstError == nil { firstError = error } }
        }

        deleteLocalProfile()
        clearScopedDefaults()

        await MainActor.run { self.signOut() }

        if let err = firstError, identity != nil { throw err }
    }

    // MARK: - Messaging convenience

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

    // MARK: - Notifications permission helper
    func requestNotificationPermissionsIfNeeded() async { }
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

    // New: save profile fields to CloudKit (used by sign-out flush)
    func saveProfile(_ profile: AppState.UserProfile, identity: String) async throws
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
    func identity(forAppID appID: UUID) async throws -> String? { nil }
    func saveProfile(_ profile: AppState.UserProfile, identity: String) async throws {
        _ = (profile, identity)
    }
}
