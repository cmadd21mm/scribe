import Foundation
import Testing

@testable import Scribe

struct SummaryEditingTests {
    private let correction = "Charlie left Strategy, the company.\n\nThe release_candidate is still under discussion."

    private func makeMeeting() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-edit-summary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"title":"Raj meeting","state":"complete"}"#.utf8)
            .write(to: dir.appendingPathComponent("meta.json"))
        try Data("""
        # Raj meeting

        ## Summary

        Original AI summary.

        ## Decisions

        - Follow up.

        ## Meeting Notes

        ### Discussion

        Original detailed notes.

        ---

        _Generated with test._
        """.utf8).write(to: dir.appendingPathComponent("note.md"))
        return dir
    }

    @Test("Edited summaries reload verbatim and reach search, copied summaries, and exports")
    @MainActor
    func saveReloadCopyExport() throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        try MeetingSummaryEdits.save(correction, to: dir)
        let meeting = try #require(MeetingLibraryReader.read(directory: dir))
        #expect(meeting.summary == correction)
        #expect(meeting.hasEditedSummary)
        #expect(meeting.searchableText.contains("charlie left strategy"))
        #expect(meeting.decisions == ["Follow up."])
        #expect(meeting.meetingNotes.contains("Original detailed notes."))
        let model = ScribeAppModel(root: FileManager.default.temporaryDirectory, demo: true)
        #expect(model.formattedSummary(for: meeting).contains(correction))
        let original = try String(contentsOf: dir.appendingPathComponent("note.md"), encoding: .utf8)
        #expect(original.contains("Original AI summary."))
        let exported = MeetingAnalysisEdits.applying(to: original, in: dir)
        #expect(exported.contains(correction))
        #expect(!exported.contains("Original AI summary."))
        #expect(exported.contains("## Decisions\n\n- Follow up."))
        #expect(exported.hasSuffix("_Generated with test._"))
    }

    private struct RegeneratingSummarizer: MeetingSummarizer {
        let backendName = "test"
        let directory: URL
        let correction: String
        func summarize(_ request: SummarizationRequest) async throws -> StructuredMeetingNote {
            try MeetingSummaryEdits.save(correction, to: directory)
            return StructuredMeetingNote(summary: "Fresh AI summary.", decisions: ["New decision."], actionItems: [], openQuestions: [],
                                         meetingNotes: [.init(topic: "Discussion", notes: "Fresh AI notes.")])
        }
    }

    @Test("Both edited sections survive regeneration including a summary edit saved during generation")
    func preserveRegeneration() async throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        try MeetingNotesEdits.save("Corrected detailed notes.", to: dir)
        try await NotePipeline.generate(sessionDir: dir, transcriptMarkdown: "Transcript",
                                        summarizer: RegeneratingSummarizer(directory: dir, correction: correction))
        let meeting = try #require(MeetingLibraryReader.read(directory: dir))
        #expect(meeting.summary == correction)
        #expect(meeting.meetingNotes == "Corrected detailed notes.")
        #expect(meeting.decisions == ["New decision."])
        let generated = try String(contentsOf: dir.appendingPathComponent("note.md"), encoding: .utf8)
        let exported = MeetingAnalysisEdits.applying(to: generated, in: dir)
        #expect(exported.contains(correction))
        #expect(exported.contains("Corrected detailed notes."))
        #expect(!exported.contains("Fresh AI"))
    }

    @Test("Empty summary edits persist without falling back to generated text")
    func emptySummary() throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        try MeetingSummaryEdits.save("", to: dir)
        let meeting = try #require(MeetingLibraryReader.read(directory: dir))
        #expect(meeting.hasEditedSummary)
        #expect(meeting.summary.isEmpty)
    }

    @Test("Export replacements use original boundaries even when edits include section headings")
    func exportBoundaries() throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        let summary = "My summary.\n\n## Meeting Notes\n\nThis heading belongs to the user's text."
        try MeetingSummaryEdits.save(summary, to: dir)
        try MeetingNotesEdits.save("My detailed notes.", to: dir)
        let original = try String(contentsOf: dir.appendingPathComponent("note.md"), encoding: .utf8)
        let exported = MeetingAnalysisEdits.applying(to: original, in: dir)
        #expect(exported.contains(summary))
        #expect(exported.contains("My detailed notes."))
        #expect(!exported.contains("Original detailed notes."))
        let legacy = MeetingAnalysisEdits.applying(to: "# Raj\n\n---\n\nFooter", in: dir)
        #expect(legacy.contains("## Summary\n\n" + summary))
        #expect(legacy.contains("## Meeting Notes\n\nMy detailed notes.\n\n---"))
    }

    @Test("Summary saves target the captured meeting without calling AI or editing detailed notes")
    @MainActor
    func saveCapturedMeeting() throws {
        let model = ScribeAppModel(root: FileManager.default.temporaryDirectory, demo: true)
        let meeting = try #require(model.meetings.first)
        model.summaryEditorMeeting = meeting
        model.selectedMeetingID = model.meetings[1].id
        let otherSummary = model.meetings[1].summary
        try model.saveSummary(correction, for: meeting.id)
        #expect(model.meetings[0].summary == correction)
        #expect(model.meetings[0].hasEditedSummary)
        #expect(model.meetings[0].meetingNotes == meeting.meetingNotes)
        #expect(model.meetings[1].summary == otherSummary)
        #expect(model.summaryEditorMeeting == nil)
        #expect(model.regeneratingMeetingID == nil)
    }

    @Test("Failed summary saves keep the editor open and the original summary intact")
    @MainActor
    func saveFailure() throws {
        let dir = try makeMeeting()
        defer { try? FileManager.default.removeItem(at: dir) }
        let meeting = try #require(MeetingLibraryReader.read(directory: dir))
        let model = ScribeAppModel(root: FileManager.default.temporaryDirectory, demo: true)
        model.meetings = [meeting]
        model.summaryEditorMeeting = meeting
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("summary-edits.md"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try model.saveSummary(correction, for: meeting.id) }
        #expect(model.summaryEditorMeeting != nil)
        #expect(model.meetings[0].summary == meeting.summary)
        #expect(!model.meetings[0].hasEditedSummary)
    }
}
