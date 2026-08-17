import EventKit
import Foundation

@MainActor
final class CalendarService {
    private let store = EKEventStore()
    private var reportedPermissionFailure = false

    func context(
        at date: Date,
        fallbackTitle: String,
        sourceBundleID: String?
    ) async -> MeetingContext {
        let fallback = MeetingContext.fallback(
            title: fallbackTitle,
            sourceBundleID: sourceBundleID
        )

        guard await ensureAccess() else { return fallback }
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

    private func ensureAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            do {
                let granted = try await store.requestFullAccessToEvents()
                if !granted { reportPermissionFailure() }
                return granted
            } catch {
                reportPermissionFailure(detail: "\(error)")
                return false
            }
        case .denied, .restricted, .writeOnly:
            reportPermissionFailure()
            return false
        @unknown default:
            reportPermissionFailure()
            return false
        }
    }

    private func reportPermissionFailure(detail: String? = nil) {
        guard !reportedPermissionFailure else { return }
        reportedPermissionFailure = true
        let suffix = detail.map { " (\($0))" } ?? ""
        let message = "Calendar access is unavailable\(suffix). Enable Quill in System Settings → Privacy & Security → Calendars. Recording will continue with an app-and-time name."
        FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
        notifyUser(title: "Quill: calendar unavailable", body: message)
    }
}
