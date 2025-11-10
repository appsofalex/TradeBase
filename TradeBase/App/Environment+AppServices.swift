import SwiftUI

// Helper to detect Xcode previews
private enum PreviewSentinel {
    static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

// One-time logger to avoid spamming the console
private struct MissingInjectionLogger {
    static var didLogAppState = false
    static var didLogJobStore = false
    // Removed: didLogMessaging
}

private struct AppStateKey: EnvironmentKey {
    static let defaultValue: AppState = {
        // In previews, silently provide a fresh instance.
        if PreviewSentinel.isPreview { return AppState() }

        #if DEBUG
        // Minimal, single-line warning without stack trace; keep app seamless.
        if MissingInjectionLogger.didLogAppState == false {
            MissingInjectionLogger.didLogAppState = true
            print("[Environment] AppState fallback in use until root injection is applied.")
        }
        return AppState()
        #else
        // In release, stay completely silent and just provide a fallback.
        return AppState()
        #endif
    }()
}

private struct CustomerJobListingStoreKey: EnvironmentKey {
    static let defaultValue: CustomerJobListingStore = {
        // In previews, silently provide a fresh instance.
        if PreviewSentinel.isPreview { return CustomerJobListingStore() }

        #if DEBUG
        // Minimal, single-line warning without stack trace; keep app seamless.
        if MissingInjectionLogger.didLogJobStore == false {
            MissingInjectionLogger.didLogJobStore = true
            print("[Environment] CustomerJobListingStore fallback in use until root injection is applied.")
        }
        return CustomerJobListingStore()
        #else
        // In release, stay completely silent and just provide a fallback.
        return CustomerJobListingStore()
        #endif
    }()
}

// Removed: MessagingControllerKey

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }

    var customerJobListingStore: CustomerJobListingStore {
        get { self[CustomerJobListingStoreKey.self] }
        set { self[CustomerJobListingStoreKey.self] = newValue }
    }

    // Removed: messagingController
}
