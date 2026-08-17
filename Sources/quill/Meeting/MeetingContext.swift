import Foundation

struct MeetingContext: Codable, Equatable, Sendable {
    let title: String
    let attendees: [String]
    let calendarEventID: String?
    let sourceBundleID: String?

    static func fallback(title: String, sourceBundleID: String?) -> MeetingContext {
        MeetingContext(
            title: title,
            attendees: [],
            calendarEventID: nil,
            sourceBundleID: sourceBundleID
        )
    }
}

struct CalendarEventCandidate: Equatable, Sendable {
    let identifier: String
    let title: String
    let start: Date
    let end: Date
    let attendees: [String]
    let isAllDay: Bool
}

enum CalendarMatcher {
    static func concurrentEvent(
        at date: Date,
        from events: [CalendarEventCandidate]
    ) -> CalendarEventCandidate? {
        events
            .filter { $0.start <= date && date <= $0.end }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay }
                let leftDistance = abs(lhs.start.timeIntervalSince(date))
                let rightDistance = abs(rhs.start.timeIntervalSince(date))
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return lhs.end.timeIntervalSince(lhs.start) < rhs.end.timeIntervalSince(rhs.start)
            }
            .first
    }
}

enum ObsidianSafeFilename {
    static func sanitize(_ raw: String, fallback: String = "Meeting") -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#[]^\n\r\t")
        let pieces = raw.components(separatedBy: forbidden)
        let collapsed = pieces
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let value = collapsed.isEmpty ? fallback : collapsed
        return String(value.prefix(100))
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}

enum MeetingFolderNamer {
    static func name(
        startedAt: Date,
        title: String,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: startedAt
        )
        let stamp = String(
            format: "%04d-%02d-%02d %02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
        return "\(stamp) - \(ObsidianSafeFilename.sanitize(title))"
    }
}
