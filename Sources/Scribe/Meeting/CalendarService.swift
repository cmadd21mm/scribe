@preconcurrency import EventKit
import Foundation

@MainActor
final class CalendarService {
    private let store = EKEventStore()

    func context(
        at date: Date,
        fallbackTitle: String,
        sourceBundleID: String?
    ) async -> MeetingContext {
        let fallback = MeetingContext.fallback(
            title: fallbackTitle,
            sourceBundleID: sourceBundleID
        )

        // Calendar naming is optional and must never delay or prevent a
        // recording. Permission is requested explicitly from Settings.
        guard Self.hasAccess else { return fallback }
        let predicate = store.predicateForEvents(
            withStart: date.addingTimeInterval(-12 * 60 * 60),
            end: date.addingTimeInterval(12 * 60 * 60),
            calendars: nil
        )
        let candidates = store.events(matching: predicate).map { event in
            CalendarEventCandidate(
                identifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                title: event.title ?? fallbackTitle,
                start: event.startDate,
                end: event.endDate,
                attendees: event.attendees?.compactMap { participant in
                    let label = participant.name ?? participant.url.absoluteString
                    return label.isEmpty ? nil : label
                } ?? [],
                isAllDay: event.isAllDay
            )
        }
        guard let event = CalendarMatcher.concurrentEvent(at: date, from: candidates) else {
            return fallback
        }
        return MeetingContext(
            title: event.title,
            attendees: event.attendees,
            calendarEventID: event.identifier,
            sourceBundleID: sourceBundleID
        )
    }

    static var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            return true
        case .notDetermined, .denied, .restricted, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }

    static func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return (try? await EKEventStore().requestFullAccessToEvents()) == true
        case .denied, .restricted, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }
}
