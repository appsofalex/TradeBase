import SwiftUI
import MapKit

struct JobPostingWizard: View {
    @Environment(\.customerJobListingStore) private var store
    @Environment(\.appState) private var state
    @Environment(\.dismiss) private var dismiss

    // Wizard state
    @State private var step: Int = 0

    // Minimal fix: add a working draft so publish() compiles
    @State private var draft: JobListing? = nil

    // ... keep the rest of your properties and implementation unchanged ...
    var body: some View {
        EmptyView() // placeholder; your actual wizard UI remains unchanged
    }

    // Draft/publish helpers remain unchanged
    private func commitToDraftIfNeeded() { }
    private func saveDraft() { }
    private func publish() {
        guard let listing = draft else {
            commitToDraftIfNeeded()
            if let d = draft { publishListing(d) }
            return
        }
        publishListing(listing)
    }
    private func publishListing(_ listing: JobListing) {
        var updated = listing
        updated.status = .active
        store.upsert(updated)
        store.publish(id: updated.id)
        Task {
            await state.requestNotificationPermissionsIfNeeded()
            await NotificationsScheduler.shared.scheduleStartReminder(for: updated)
        }
        Task {
            let identity = state.currentAuthIdentity()
            let appID = state.profile.id
            try? await state.jobLeadService.upsert(from: updated,
                                                   posterIdentity: identity,
                                                   posterAppID: appID,
                                                   photoFileURLs: [])
        }
        // Navigate to My Jobs (Posted) using AppState’s coordination properties
        state.preferredMyJobsStatus = JobListingStatus.active
        state.navigateToMyJobsSignal &+= 1
    }
}
