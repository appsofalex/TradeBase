// ProfileStore.swift
import Foundation

actor ProfileStore {
    private let directoryURL: URL
    // Legacy single-file path (kept for backward compatibility if needed)
    private let fileURL: URL

    init(filename: String = "UserProfile.json") {
        let fm = FileManager.default

        // Resolve Application Support/TradeBase directory
        let baseDir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let appDir = baseDir.appendingPathComponent("TradeBase", isDirectory: true)

        // Ensure directory exists
        if !fm.fileExists(atPath: appDir.path) {
            try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        }

        // Apply strong file protection on the directory (inherited by new files)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: appDir.path)

        self.directoryURL = appDir
        self.fileURL = appDir.appendingPathComponent(filename)

        // Migrate from old Documents location if present
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let oldURL = docs.appendingPathComponent(filename)
            if fm.fileExists(atPath: oldURL.path), !fm.fileExists(atPath: fileURL.path) {
                try? fm.moveItem(at: oldURL, to: fileURL)
                // Ensure protection on migrated file
                try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
            }
        }
    }

    // MARK: - Identity-aware paths

    private func sanitizeIdentity(_ raw: String) -> String {
        // Keep alphanumerics, dash, underscore; replace everything else with '-'
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    private func urlForIdentity(_ identity: String?) -> URL {
        let name: String
        if let id = identity, !id.isEmpty {
            name = "UserProfile_\(sanitizeIdentity(id)).json"
        } else {
            name = "UserProfile_guest.json"
        }
        return directoryURL.appendingPathComponent(name)
    }

    // MARK: - Load/Save (identity-aware)

    func load(identity: String?) async -> UserProfile? {
        let url = urlForIdentity(identity)
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(UserProfile.self, from: data)
        } catch {
            // No saved profile yet or decode failed
            return nil
        }
    }

    func save(_ profile: UserProfile, identity: String?) async throws {
        let url = urlForIdentity(identity)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        // Atomic write, then set protection on the file
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)

        // If you want to keep this strictly on-device without iCloud backup, uncomment:
        // var rvs = URLResourceValues()
        // rvs.isExcludedFromBackup = true
        // try? url.setResourceValues(rvs)
    }

    // Legacy wrappers (default to guest identity)
    func load() async -> UserProfile? {
        await load(identity: nil)
    }

    func save(_ profile: UserProfile) async throws {
        try await save(profile, identity: nil)
    }

    // MARK: - Delete (identity-aware)

    func delete(identity: String?) async throws {
        let url = urlForIdentity(identity)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    func delete() async throws {
        try await delete(identity: nil)
    }

    // MARK: - Avatar file management

    // Generate a unique filename for each avatar save to bust caches and force UI refresh.
    func saveAvatar(_ data: Data, filename: String? = nil) async throws -> URL {
        let fm = FileManager.default
        let avatarsDir = directoryURL.appendingPathComponent("Avatars", isDirectory: true)
        if !fm.fileExists(atPath: avatarsDir.path) {
            try fm.createDirectory(at: avatarsDir, withIntermediateDirectories: true)
            try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: avatarsDir.path)
        }

        // Use provided filename if supplied; otherwise generate a unique one.
        let uniqueName = filename ?? "avatar-\(UUID().uuidString).jpg"
        var url = avatarsDir.appendingPathComponent(uniqueName)

        try data.write(to: url, options: [.atomic])
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)

        var rvs = URLResourceValues()
        rvs.isExcludedFromBackup = true
        try? url.setResourceValues(rvs)

        return url
    }

    func deleteAvatarIfLocal(url: URL?) async {
        guard let url else { return }
        let fm = FileManager.default
        // Only delete if stored within our app support directory
        if url.path.hasPrefix(directoryURL.path) {
            try? fm.removeItem(at: url)
        }
    }
}
