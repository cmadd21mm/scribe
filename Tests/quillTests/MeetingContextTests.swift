import Foundation
import Testing

@testable import quill

struct MeetingContextTests {
    @Test("Calendar matching prefers a concurrent non-all-day event nearest its start")
    func matchesConcurrentMeeting() {
        let now = Date(timeIntervalSince1970: 10_000)
        let allDay = event("all-day", start: now.addingTimeInterval(-1_000), allDay: true)
        let older = event("older", start: now.addingTimeInterval(-600))
        let current = event("current", start: now.addingTimeInterval(-60))
        let future = event("future", start: now.addingTimeInterval(60))

        #expect(CalendarMatcher.concurrentEvent(
            at: now,
            from: [allDay, older, current, future]
        )?.identifier == "current")
    }

    @Test("Filename sanitization removes filesystem and Obsidian syntax")
    func safeFilename() {
        #expect(
            ObsidianSafeFilename.sanitize("  Q3 / plan: [launch] #1?  ")
                == "Q3 plan launch 1"
        )
        #expect(ObsidianSafeFilename.sanitize("///") == "Meeting")
    }

    @Test("Folder names are stable and sortable")
    func folderName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 1,
            hour: 12,
            minute: 25,
            second: 10
        ))!
        #expect(MeetingFolderNamer.name(
            startedAt: date,
            title: "Product / Weekly",
            calendar: calendar
        ) == "2026-01-01 1225 - Product Weekly")
    }

    @Test("A meeting folder starts with an Obsidian-safe note and versioned metadata")
    func meetingFolderLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let context = MeetingContext(
            title: "Design / review",
            attendees: ["Ada", "Grace"],
            calendarEventID: "event-1",
            sourceBundleID: "us.zoom.xos"
        )
        let meeting = try RecordingSession(root: root, context: context)
        meeting.stop()

        #expect(meeting.dir.lastPathComponent.contains("Design review"))
        let note = try String(
            contentsOf: meeting.dir.appendingPathComponent("note.md"),
            encoding: .utf8
        )
        #expect(note.contains("# Design / review"))
        #expect(note.contains("- Ada\n- Grace"))
        let metadata = try JSONSerialization.jsonObject(
            with: Data(contentsOf: meeting.dir.appendingPathComponent("meta.json"))
        ) as? [String: Any]
        #expect(metadata?["schema_version"] as? Int == 1)
        #expect(metadata?["title"] as? String == "Design / review")
    }

    private func event(
        _ id: String,
        start: Date,
        allDay: Bool = false
    ) -> CalendarEventCandidate {
        CalendarEventCandidate(
            identifier: id,
            title: id,
            start: start,
            end: start.addingTimeInterval(3_600),
            attendees: [],
            isAllDay: allDay
        )
    }
}
