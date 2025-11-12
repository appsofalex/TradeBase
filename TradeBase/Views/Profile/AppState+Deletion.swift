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

    // MARK: - Role-aware delete helpers

    /// Delete a TRADESPERSON account and reset setup gating so setup runs again next time.
    func deleteTradespersonAccountAndResetSetup(resetUnauthOnboarding: Bool = false) async throws {
        // Capture identity before it is cleared by signOut()
        let id = currentAuthIdentity()
        try await deleteAccountComprehensive()

        // Remove from registered set so needsSetup(for: .tradesperson) returns true for this identity
        if let id {
            registeredTradespersonAccounts.remove(id)
            UserDefaults.standard.set(Array(registeredTradespersonAccounts), forKey: Self.registeredTradespersonAccountsKey)
        }

        // Ensure setup gating is reset for next authenticated session
        await MainActor.run {
            self.tradespersonSetupCompleted = false
            if resetUnauthOnboarding {
                self.tradespersonOnboardingCompleted = false
            }
        }
    }

    /// Delete a CUSTOMER account and reset setup gating so setup runs again next time.
    func deleteCustomerAccountAndResetSetup(resetUnauthOnboarding: Bool = false) async throws {
        let id = currentAuthIdentity()
        try await deleteAccountComprehensive()

        if let id {
            registeredCustomerAccounts.remove(id)
            UserDefaults.standard.set(Array(registeredCustomerAccounts), forKey: Self.registeredCustomerAccountsKey)
        }

        await MainActor.run {
            self.customerSetupCompleted = false
            if resetUnauthOnboarding {
                self.customerOnboardingCompleted = false
            }
        }
    }
}
