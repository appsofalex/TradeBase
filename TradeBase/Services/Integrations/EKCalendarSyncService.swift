//
//  EKCalendarSyncService.swift
//  TradeBase
//
//  Created by Alex Walters on 16/09/2025.
//

import Foundation
import EventKit

@MainActor
final class EKCalendarSyncService: CalendarSyncService {
    private let store = EKEventStore()

    func requestAccess() async throws {
        try await store.requestFullAccessToEvents()
    }

    func export(job: Job) async throws {
        let calendars = store.calendars(for: .event)
        let calendar = calendars.first(where: { $0.allowsContentModifications }) ?? store.defaultCalendarForNewEvents
        guard let calendar else { return }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = "Job: \(job.title) — \(job.clientName)"
        event.startDate = job.scheduledStart
        event.endDate = job.scheduledStart.addingTimeInterval(job.estimatedHours * 3600)
        event.location = "\(job.address.line1), \(job.address.city) \(job.address.postcode)"
        event.notes  = job.notes

        try store.save(event, span: .thisEvent)
    }
}
