import Foundation
import UserNotifications

final class NotificationsScheduler {
    static let shared = NotificationsScheduler()

    func scheduleDraftReminder(for listing: JobListing, hoursFromNow: Int = 24) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Finish your job draft"
        content.body = "Don’t forget to publish “\(listing.title.isEmpty ? "Untitled job" : listing.title)”."
        content.userInfo = ["jobID": listing.id.uuidString]

        let triggerDate = Date().addingTimeInterval(TimeInterval(hoursFromNow * 3600))
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: "draft-\(listing.id.uuidString)", content: content, trigger: trigger)
        try? await center.add(req)
    }

    func scheduleStartReminder(for listing: JobListing) async {
        guard let start = listing.startDate else { return }
        // Day before at 9am local
        let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start
        let dateAtNine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore) ?? dayBefore

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Upcoming job"
        content.body = "“\(listing.title.isEmpty ? "Job" : listing.title)” starts soon."
        content.userInfo = ["jobID": listing.id.uuidString]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dateAtNine)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: "start-\(listing.id.uuidString)", content: content, trigger: trigger)
        try? await center.add(req)
    }

    func cancelAllForListing(id: UUID) {
        let center = UNUserNotificationCenter.current()
        let ids = ["draft-\(id.uuidString)", "start-\(id.uuidString)"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
