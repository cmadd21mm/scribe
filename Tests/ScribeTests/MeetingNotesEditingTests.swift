import Foundation
import Testing

@testable import Scribe

struct MeetingNotesEditingTests {
    private let corrected = "### Career transition\n\nCharlie worked at Strategy, the company.\n\nThe release_candidate remains open."

    private func makeMeeting() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-edit-notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"title":"Raj meeting","state":"complete"}"#.utf8)
            .write(to: dir.appendingPathComponent("meta.json"))
        try Data("""
        # Raj meeting

        ## Summary

        Summary stays intact.

        ## Meeting Notes

        ### Career transition

        Incorrect generated text.

        ## Action items

        - [ ] Follow up with Raj.

        ---

        _Generated with test._
        """.utf8).write(to: dir.appendingPathComponent("note.md"))
        return dir
    }

    @Test("Edits persist separately, appear in search, and export without changing other sections")
    func saveReloadExport() throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = try String(contentsOf: dir.appendingPathComponent("note.md"), encoding: .utf8)
        try MeetingNotesEdits.save(corrected, to: dir)
        let meeting = try #require(MeetingLibraryReader.read(directory: dir))
        #expect(meeting.meetingNotes == corrected)
        #expect(meeting.hasEditedMeetingNotes)
        #expect(meeting.searchableText.contains("worked at strategy"))
        #expect(meeting.summary == "Summary stays intact.")
        #expect(meeting.actionItems.first?.text == "Follow up with Raj.")
        #expect(meeting.userNotes.isEmpty)
        #expect(try String(contentsOf: dir.appendingPathComponent("note.md"), encoding: .utf8) == original)
        let exported = MeetingNotesEdits.applying(to: original, in: dir)
        #expect(exported.contains(corrected))
        #expect(!exported.contains("Incorrect generated text."))
        #expect(exported.contains("## Action items\n\n- [ ] Follow up with Raj."))
        #expect(exported.contains("_Generated with test._"))
    }

    private struct RegeneratingSummarizer: MeetingSummarizer {
        let backendName = "test"
        let directory: URL
        let correction: String
        func summarize(_ request: SummarizationRequest) async throws -> StructuredMeetingNote {
            // Simulate an edit saved while a generation request is in flight.
            try MeetingNotesEdits.save(correction, to: directory)
            return StructuredMeetingNote(summary: "Fresh summary", decisions: [], actionItems: [], openQuestions: [],
                                         meetingNotes: [.init(topic: "Career", notes: "Old misconception from the transcript.")])
        }
    }

    @Test("Edits saved during regeneration remain authoritative when the result arrives")
    func preserveDuringRegeneration() async throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await NotePipeline.generate(sessionDir: dir, transcriptMarkdown: "Transcript",
                                        summarizer: RegeneratingSummarizer(directory: dir, correction: corrected))
        let meeting = try #require(MeetingLibraryReader.read(directory: dir))
        #expect(meeting.summary == "Fresh summary")
        #expect(meeting.meetingNotes == corrected)
        let generated = try String(contentsOf: dir.appendingPathComponent("note.md"), encoding: .utf8)
        let exported = MeetingNotesEdits.applying(to: generated, in: dir)
        #expect(exported.contains(corrected))
        #expect(!exported.contains("Old misconception"))
    }

    @Test("Intentionally empty edits never fall back to the incorrect AI text")
    func emptyEdits() throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        try MeetingNotesEdits.save("", to: dir)
        let meeting = try #require(MeetingLibraryReader.read(directory: dir))
        #expect(meeting.hasEditedMeetingNotes)
        #expect(meeting.meetingNotes.isEmpty)
        let exported = MeetingNotesEdits.applying(to: "## Meeting Notes\n\nIncorrect generated text.", in: dir)
        #expect(!exported.contains("Incorrect"))
    }

    @Test("Older exports without a notes section include edits before the footer")
    func legacyExport() throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        try MeetingNotesEdits.save(corrected, to: dir)
        let exported = MeetingNotesEdits.applying(to: "# Raj\n\n## Summary\n\nExisting summary.\n\n---\n\nFooter.", in: dir)
        #expect(exported.contains("## Summary\n\nExisting summary."))
        #expect(exported.contains("## Meeting Notes\n\n" + corrected + "\n\n---\n\nFooter."))
    }

    @Test("Saving targets the edited meeting even if selection changed and never starts AI")
    @MainActor
    func savesCapturedMeeting() throws {
        let model = ScribeAppModel(root: FileManager.default.temporaryDirectory, demo: true)
        let meeting = try #require(model.meetings.first)
        model.meetingNotesEditorMeeting = meeting
        model.selectedMeetingID = model.meetings[1].id
        try model.saveMeetingNotes(corrected, for: meeting.id)
        #expect(model.meetings.first?.meetingNotes == corrected)
        #expect(model.meetings[1].meetingNotes.isEmpty)
        #expect(model.meetingNotesEditorMeeting == nil)
        #expect(model.regeneratingMeetingID == nil)
        #expect(model.formattedMeetingNotes(for: model.meetings[0]).contains(corrected))
    }

    @Test("A failed save keeps the editor open and leaves displayed notes unchanged")
    @MainActor
    func saveFailureKeepsDraft() throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = ScribeAppModel(root: FileManager.default.temporaryDirectory, demo: true)
        let meeting = try #require(MeetingLibraryReader.read(directory: dir))
        model.meetings = [meeting]
        model.meetingNotesEditorMeeting = meeting
        // A directory at the destination reliably causes an atomic file write to fail.
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("meeting-notes.md"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try model.saveMeetingNotes(corrected, for: meeting.id) }
        #expect(model.meetings.first?.meetingNotes == meeting.meetingNotes)
        #expect(model.meetingNotesEditorMeeting != nil)
    }
}
