import Foundation
import Testing

@testable import Scribe

struct DetailedMeetingNotesTests {
    @Test("Detailed topics survive model output, Markdown storage, and library loading")
    func detailedNotesRoundTrip() throws {
        let output = #"""
        {"summary":"The rollout is still under discussion.","decisions":[],"actionItems":[],"openQuestions":["Can support cover the pilot?"],"meetingNotes":[{"topic":"Rollout options","notes":"The team considered a phased rollout because support is at capacity. Alex raised concerns about enterprise delays; no exception was agreed."},{"topic":"Capacity and timing","notes":"The pilot would include 12 accounts. The proposed date is September 30, subject to support coverage.\n\nThe release_candidate flag remains disabled."}]}
        """#
        let note = try SummaryOutputParser.parse(output)
        #expect(note.meetingNotes?.count == 2)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-detailed-notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"title":"Rollout review","state":"complete"}"#.utf8)
            .write(to: directory.appendingPathComponent("meta.json"))
        let markdown = NoteRenderer.render(
            context: .fallback(title: "Rollout review", sourceBundleID: nil),
            note: note,
            backendName: "test"
        )
        try Data(markdown.utf8).write(to: directory.appendingPathComponent("note.md"))
        let meeting = try #require(MeetingLibraryReader.read(directory: directory))
        #expect(meeting.summary == note.summary)
        #expect(meeting.openQuestions == note.openQuestions)
        #expect(meeting.meetingNotes.contains("### Rollout options\n\nThe team considered"))
        #expect(meeting.meetingNotes.contains("### Capacity and timing"))
        #expect(meeting.meetingNotes.contains("release_candidate"))
        #expect(!meeting.meetingNotes.contains("Generated locally"))
        #expect(meeting.searchableText.contains("12 accounts"))
        #expect(meeting.userNotes.isEmpty)
    }

    @Test("Older model responses and saved meetings remain readable without detailed notes")
    func legacyNotes() throws {
        let note = try SummaryOutputParser.parse(#"{"summary":"Existing summary.","decisions":[],"actionItems":[],"openQuestions":[]}"#)
        #expect(note.meetingNotes == nil)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-legacy-detail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"title":"Review"}"#.utf8).write(to: directory.appendingPathComponent("meta.json"))
        for markdown in [
            "# Review\n\n## Summary\n\nExisting summary.",
            NoteRenderer.render(context: .fallback(title: "Review", sourceBundleID: nil), note: note, backendName: "test"),
        ] {
            try Data(markdown.utf8).write(to: directory.appendingPathComponent("note.md"))
            let meeting = try #require(MeetingLibraryReader.read(directory: directory))
            #expect(meeting.summary == "Existing summary.")
            #expect(meeting.meetingNotes.isEmpty)
        }
    }

    @Test("Copying meeting notes includes their title without mixing in personal notes")
    @MainActor
    func copyDetailedNotes() throws {
        let model = ScribeAppModel(root: FileManager.default.temporaryDirectory, demo: true)
        let meeting = try #require(model.meetings.first)
        let text = model.formattedMeetingNotes(for: meeting)
        #expect(text.hasPrefix("# \(meeting.title)\n\n## Meeting Notes"))
        #expect(!meeting.meetingNotes.isEmpty)
        #expect(text.contains(meeting.meetingNotes))
        #expect(!text.contains(meeting.userNotes))
        #expect(!model.formattedSummary(for: meeting).contains("### Beta scope and reporting"))
    }

    @Test("Strict structured output permits and requires detailed discussion topics")
    func structuredOutputSchema() throws {
        let body = ScribeRemoteAIClient.openAICompatibleBody(
            prompt: "Meeting notes",
            settings: .init(provider: .venice, model: "test", baseURL: "", redactSensitive: true),
            maxTokens: MeetingNoteInstructions.outputTokens,
            structuredMeetingNote: true
        )
        let format = try #require(body["response_format"] as? [String: Any])
        let jsonSchema = try #require(format["json_schema"] as? [String: Any])
        let schema = try #require(jsonSchema["schema"] as? [String: Any])
        #expect((schema["required"] as? [String])?.contains("meetingNotes") == true)
        let properties = try #require(schema["properties"] as? [String: Any])
        let notes = try #require(properties["meetingNotes"] as? [String: Any])
        #expect(notes["type"] as? String == "array")
        let item = try #require(notes["items"] as? [String: Any])
        #expect(item["required"] as? [String] == ["topic", "notes"])
        #expect(item["additionalProperties"] as? Bool == false)
    }
}
