//
//  CustomerJobListingStore.swift
//  TradeBase
//

import Foundation
import Observation

enum JobBudgetType: String, Codable, CaseIterable, Identifiable {
    case quote, fixed, hourly, range
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quote:
            return "Quote"
        case .fixed:
            return "Fixed"
        case .hourly:
            return "Hourly"
        case .range:
            return "Range"
        }
    }

    // Only control what the UI shows; keep .range in the enum for back-compat.
    static var uiOrder: [JobBudgetType] { [.quote, .fixed, .hourly] }
}

enum JobListingStatus: String, Codable, CaseIterable, Identifiable {
    case draft, active, inProgress, completed, closed
    var id: String { rawValue }
}

struct JobListing: Identifiable, Codable, Hashable {
    var id = UUID()
    var ownerUserId: UUID
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var status: JobListingStatus = .draft

    var category: TradeType?
    var title: String
    var description: String

    var location: Address
    var photos: [URL] = []

    var budgetType: JobBudgetType = .fixed
    var budgetMin: Decimal? = nil
    var budgetMax: Decimal? = nil
    var currency: String = "GBP"

    var startDate: Date? = nil
    var isFlexibleTiming: Bool = true
    var isUrgent: Bool = false

    var contactEmail: String? = nil
    var contactPhone: String? = nil
}

@Observable
final class CustomerJobListingStore {
    var listings: [JobListing] = []

    // MARK: - Identity scoping

    private var identity: String? = nil {
        didSet {
            // Switch persistence file and reload
            currentPersistenceURL = makePersistenceURL(for: identity)
            load()
        }
    }

    // MARK: - Persistence

    private let baseAppDir: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let appDir = base.appendingPathComponent("TradeBase", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) {
            try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)
        return appDir
    }()

    private var currentPersistenceURL: URL

    init(identity: String? = nil) {
        self.currentPersistenceURL = URL(fileURLWithPath: "/dev/null")
        self.identity = identity
        self.currentPersistenceURL = makePersistenceURL(for: identity)
        load()
    }

    private func sanitizeIdentity(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    private func makePersistenceURL(for identity: String?) -> URL {
        let name: String
        if let id = identity, !id.isEmpty {
            name = "JobListings_\(sanitizeIdentity(id)).json"
        } else {
            name = "JobListings_guest.json"
        }
        return baseAppDir.appendingPathComponent(name, isDirectory: false)
    }

    /// Switch the store to a new identity (e.g., after sign-in/out) and reload from its file.
    func setIdentity(_ newIdentity: String?) {
        identity = newIdentity
    }

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: currentPersistenceURL.path) else {
            self.listings = []
            return
        }
        do {
            let data = try Data(contentsOf: currentPersistenceURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([JobListing].self, from: data)
            self.listings = decoded
        } catch {
            print("Job listings load failed: \(error)")
            self.listings = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(listings)
            try data.write(to: currentPersistenceURL, options: [.atomic])
        } catch {
            print("Job listings save failed: \(error)")
        }
    }

    // MARK: - CRUD

    func createDraft(for owner: UUID, title: String) -> JobListing {
        var draft = JobListing(
            ownerUserId: owner,
            title: title,
            description: "",
            location: Address(line1: "", city: "", postcode: "")
        )
        listings.append(draft)
        save()
        return draft
    }

    func upsert(_ listing: JobListing) {
        let now = Date()
        if let idx = listings.firstIndex(where: { $0.id == listing.id }) {
            var copy = listing
            copy.updatedAt = now
            listings[idx] = copy
        } else {
            var copy = listing
            copy.updatedAt = now
            listings.append(copy)
        }
        save()
    }

    func publish(id: UUID) {
        guard let idx = listings.firstIndex(where: { $0.id == id }) else { return }
        listings[idx].status = .active
        listings[idx].updatedAt = Date()
        save()
    }

    func close(id: UUID) {
        guard let idx = listings.firstIndex(where: { $0.id == id }) else { return }
        listings[idx].status = .closed
        listings[idx].updatedAt = Date()
        save()
    }

    func delete(id: UUID) {
        // Find the index first (read-only), then perform a single mutation.
        guard let idx = listings.firstIndex(where: { $0.id == id }) else { return }
        listings.remove(at: idx)
        save()
    }

    // New: status helpers for quick menu
    func markInProgress(id: UUID) {
        guard let idx = listings.firstIndex(where: { $0.id == id }) else { return }
        listings[idx].status = .inProgress
        listings[idx].updatedAt = Date()
        save()
    }

    func markCompleted(id: UUID) {
        guard let idx = listings.firstIndex(where: { $0.id == id }) else { return }
        listings[idx].status = .completed
        listings[idx].updatedAt = Date()
        save()
    }

    func markDraft(id: UUID) {
        guard let idx = listings.firstIndex(where: { $0.id == id }) else { return }
        listings[idx].status = .draft
        listings[idx].updatedAt = Date()
        save()
    }

    // Unscoped (legacy) status filter
    func byStatus(_ status: JobListingStatus) -> [JobListing] {
        listings.filter { $0.status == status }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // Scoped status filter by owner identity
    func byStatus(_ status: JobListingStatus, ownerId: UUID) -> [JobListing] {
        listings
            .filter { $0.ownerUserId == ownerId && $0.status == status }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // Convenience to fetch all listings for an owner (optional helper)
    func all(for ownerId: UUID) -> [JobListing] {
        listings.filter { $0.ownerUserId == ownerId }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
