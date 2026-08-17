import Foundation
import Testing

@testable import quill

struct MeetingLibraryTests {
    @Test("The library reads generated meeting folders and local user state")
    func readsMeetingFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-library-\(UUID().uuidString)", isDirectory: true)
        let meeting = root.appendingPathComponent("2026-08-17 1002 - Product planning", isDirectory: true)
        try FileManager.default.createDirectory(at: meeting, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(#"{"state":"complete","started":"2026-08-17T14:02:00Z","duration_seconds":2520,"title":"Product planning","source_bundle_id":"us.zoom.xos"}"#.utf8)
            .write(to: meeting.appendingPathComponent("meta.json"))
        try Data("""
        # Product planning
        ## Summary
        Aligned on the beta plan.
        ## Action Items
        - [ ] Priya: Finalize scope.
        """.utf8).write(to: meeting.appendingPathComponent("note.md"))
        try Data(#"{"segments":[{"speaker":"me","start_ms":5000,"text":"Let's begin."},{"speaker":"them","start_ms":8000,"text":"Ready."}]}"#.utf8)
            .write(to: meeting.appendingPathComponent("transcript.json"))
        try Data("Remember the customer example.".utf8)
            .write(to: meeting.appendingPathComponent("user-notes.md"))
        try JSONEncoder().encode([0]).write(to: meeting.appendingPathComponent("action-state.json"))

        let result = try #require(MeetingLibraryReader.read(directory: meeting))
        #expect(result.title == "Product planning")
        #expect(result.sourceName == "Zoom")
        #expect(result.summary == "Aligned on the beta plan.")
        #expect(result.actionItems.first?.isComplete == true)
        #expect(result.transcript.map(\.speaker) == ["YOU", "OTHERS"])
        #expect(result.userNotes == "Remember the customer example.")
    }

    @Test("Search includes transcript, action items, and personal notes")
    func searchCorpus() {
        let meeting = MeetingRecord.demoMeetings().first!
        #expect(meeting.searchableText.contains("beta scope"))
        #expect(meeting.searchableText.contains("simpler setup"))
        #expect(meeting.searchableText.contains("jordan"))
    }
}
