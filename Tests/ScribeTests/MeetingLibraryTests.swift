import Foundation
import Testing

@testable import Scribe

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
        try JSONEncoder().encode(["me": "Charlie", "them": "Maya"])
            .write(to: meeting.appendingPathComponent("speaker-names.json"))

        let result = try #require(MeetingLibraryReader.read(directory: meeting))
        #expect(result.title == "Product planning")
        #expect(result.sourceName == "Zoom")
        #expect(result.summary == "Aligned on the beta plan.")
        #expect(result.actionItems.first?.isComplete == true)
        #expect(result.transcript.map(\.speaker) == ["Charlie", "Maya"])
        #expect(result.userNotes == "Remember the customer example.")
    }

    @Test("Search includes transcript, action items, and personal notes")
    func searchCorpus() {
        let meeting = MeetingRecord.demoMeetings().first!
        #expect(meeting.searchableText.contains("beta scope"))
        #expect(meeting.searchableText.contains("simpler setup"))
        #expect(meeting.searchableText.contains("jordan"))
    }

    @Test("Renaming a meeting updates its folder, metadata, and Markdown titles")
    func renamesMeetingEverywhere() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-rename-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("2026-08-17 1002 - Untitled meeting", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(#"{"state":"complete","started":"2026-08-17T14:02:00Z","duration_seconds":60,"title":"Untitled meeting"}"#.utf8)
            .write(to: directory.appendingPathComponent("meta.json"))
        try Data("# Untitled meeting\n\n## Summary\n\nUseful context.".utf8)
            .write(to: directory.appendingPathComponent("note.md"))
        try Data("# Untitled meeting\n\n## Transcript\n".utf8)
            .write(to: directory.appendingPathComponent("transcript.md"))

        let original = try #require(MeetingLibraryReader.read(directory: directory))
        let renamed = try MeetingLibraryReader.rename(original, to: "Customer kickoff")

        #expect(renamed.title == "Customer kickoff")
        #expect(renamed.directory.lastPathComponent.contains("Customer kickoff"))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let metadata = try String(contentsOf: renamed.directory.appendingPathComponent("meta.json"), encoding: .utf8)
        let note = try String(contentsOf: renamed.directory.appendingPathComponent("note.md"), encoding: .utf8)
        let transcript = try String(contentsOf: renamed.directory.appendingPathComponent("transcript.md"), encoding: .utf8)
        #expect(metadata.contains("Customer kickoff"))
        #expect(note.hasPrefix("# Customer kickoff"))
        #expect(transcript.hasPrefix("# Customer kickoff"))
    }

    @Test("An empty meeting name is rejected without changing files")
    func rejectsEmptyRename() throws {
        let meeting = MeetingRecord.demoMeetings().first!
        #expect(throws: MeetingLibraryReader.LibraryError.self) {
            try MeetingLibraryReader.rename(meeting, to: "  ")
        }
    }

    @Test("Legacy two-track meetings are not mislabeled as in person")
    func legacyOnlineMeetingSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"state":"complete","title":"Call","files":{"mic":"mic.caf","system":"system.caf"}}"#.utf8)
            .write(to: root.appendingPathComponent("meta.json"))
        try Data().write(to: root.appendingPathComponent("system.caf"))

        let meeting = try #require(MeetingLibraryReader.read(directory: root))
        #expect(meeting.sourceName == "Online meeting")
    }

    @Test("A saved source name takes precedence over legacy metadata")
    func sourceNameOverride() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-source-override-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"state":"complete","title":"Call"}"#.utf8)
            .write(to: root.appendingPathComponent("meta.json"))
        try MeetingLibraryReader.setSourceName("Google Meet", for: root)

        let meeting = try #require(MeetingLibraryReader.read(directory: root))
        #expect(meeting.sourceName == "Google Meet")
    }
}
