// AppState+Deletion.swift

import Foundation

extension AppState {

    /// Permanently deletes the current account and associated data.
    /// This is best-effort for remote services; failures will throw to the caller.
    func deleteAccountComprehensive() async throws {
        // Capture current identity and local resources to remove.
        let identity = self.currentAuthIdentity()
        let avatarURL = profile.avatarURL
        let certs = profile.certifications

        // 1) Remote deletions (best-effort; throw only on profile delete if it fails explicitly)
        if let id = identity {
            // Remove avatar asset (ignore errors)
            do {
                try await cloudProfileStore.removeAvatarAsset(identity: id)
            } catch {
                // ignore best-effort
            }

            // Delete certifications remotely (ignore errors per item)
            for cert in certs {
                do {
                    try await cloudProfileStore.deleteCertification(id: cert.id)
                } catch {
                    // ignore best-effort per item
                }
            }

            // Delete the user profile record (surface error if it fails)
            try await cloudProfileStore.deleteUserProfile(identity: id)
        }

        // 2) Local file cleanup (best-effort)
        if let old = avatarURL, old.isFileURL {
            try? FileManager.default.removeItem(at: old)
        }
        for cert in certs {
            if let url = cert.fileURL, url.isFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // 3) Clear local persisted profile for this identity
        self.deleteLocalProfile()

        // 4) Clear identity-scoped UserDefaults keys and registrations
        self.clearScopedDefaults()

        // 5) Reset in-memory state to defaults
        await MainActor.run {
            self.profile = AppState.defaultProfile()
            self.conversations = []
            self.messagesCache = [:]
            self.savedLeadIDs = []
            self.hiddenLeadIDs = []
            self.updateAppIconBadge()
        }

        // 6) Sign out to end the session
        await MainActor.run {
            self.signOut()
        }
    }
}

