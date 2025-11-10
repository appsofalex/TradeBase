// AppState+Setup.swift

import Foundation

extension AppState {

    // Whether the current authenticated user still needs to complete setup for a role.
    func needsSetup(for role: UserRole) -> Bool {
        guard isAuthenticated else { return false }
        let identity = currentAuthIdentity()

        switch role {
        case .customer:
            if customerSetupCompleted { return false }
            if let id = identity {
                return !registeredCustomerAccounts.contains(id)
            }
            return true

        case .tradesperson:
            if tradespersonSetupCompleted { return false }
            if let id = identity {
                return !registeredTradespersonAccounts.contains(id)
            }
            return true
        }
    }

    // Mark setup complete for the current authenticated identity (Customer).
    func completeCustomerSetup() {
        customerSetupCompleted = true
        if let id = currentAuthIdentity() {
            registeredCustomerAccounts.insert(id)
            UserDefaults.standard.set(Array(registeredCustomerAccounts), forKey: Self.registeredCustomerAccountsKey)
        }
    }

    // Mark setup complete for the current authenticated identity (Tradesperson).
    func completeTradespersonSetup() {
        tradespersonSetupCompleted = true
        if let id = currentAuthIdentity() {
            registeredTradespersonAccounts.insert(id)
            UserDefaults.standard.set(Array(registeredTradespersonAccounts), forKey: Self.registeredTradespersonAccountsKey)
        }
    }

    // Overload used by TradespersonSetupFlow and profile settings to persist details, then mark complete.
    func completeTradespersonSetup(
        name: String,
        primaryTrade: TradeType,
        skills: [String],
        bio: String? = nil
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Update in-memory profile
        if !trimmedName.isEmpty {
            profile.name = trimmedName
        }
        profile.tradeTypes = [primaryTrade]
        profile.skills = Array(Set(skills)).sorted()
        profile.bio = trimmedBio

        // Persist profile changes (local + CloudKit mirror when signed in)
        saveProfile()

        // Mark setup complete and register this identity
        completeTradespersonSetup()
    }
}
