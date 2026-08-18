import Foundation
import Testing

@testable import Scribe

struct NotePipelineTests {
    private struct FixedRemoteSummarizer: MeetingSummarizer {
        let backendName = "Venice AI · kimi-k3"

        func summarize(_ request: SummarizationRequest) async throws -> StructuredMeetingNote {
            StructuredMeetingNote(
                summary: "The team approved the launch plan.",
                decisions: ["Launch on Friday."],
                actionItems: [.init(task: "Send the final invite.", owner: "Priya", due: "Thursday")],
                openQuestions: []
            )
        }
    }

    @Test("Local model JSON is parsed even when surrounded by chatter")
    func parsesModelOutput() throws {
        let output = """
        result:
        {"summary":"Launch is Friday.","decisions":["Ship Friday"],"actionItems":[{"task":"Send invite","owner":"Ada","due":null}],"openQuestions":[]}
        done
        """
        let note = try SummaryOutputParser.parse(output)
        #expect(note.summary == "Launch is Friday.")
        #expect(note.decisions == ["Ship Friday"])
        #expect(note.actionItems.first?.owner == "Ada")
    }

    @Test("Structured notes render every required section")
    func rendersStructuredNote() {
        let context = MeetingContext(
            title: "Launch review",
            attendees: ["Ada"],
            calendarEventID: nil,
            sourceBundleID: nil
        )
        let note = StructuredMeetingNote(
            summary: "We reviewed launch readiness.",
            decisions: ["Ship Friday"],
            actionItems: [.init(task: "Send invite", owner: "Ada", due: "Thursday")],
            openQuestions: ["Who is on call?"]
        )
        let markdown = NoteRenderer.render(
            context: context,
            note: note,
            backendName: "test-local"
        )
        for heading in ["## Summary", "## Decisions", "## Action items", "## Open questions"] {
            #expect(markdown.contains(heading))
        }
        #expect(markdown.contains("- [ ] Send invite — **Owner:** Ada — **Due:** Thursday"))
        #expect(markdown.contains("Generated locally with test-local"))
    }

    @Test("Missing local model is stated explicitly without hiding the transcript")
    func rendersUnavailableState() {
        let markdown = NoteRenderer.unavailable(
            context: .fallback(title: "Call", sourceBundleID: nil),
            reason: "no local summarization model is configured"
        )
        #expect(markdown.contains("Structured notes were not generated"))
        #expect(markdown.contains("no local summarization model"))
        #expect(markdown.contains("[transcript](transcript.md)"))
        #expect(markdown.contains("did not make a network call"))
    }

    @Test("Built-in notes never guess decisions or assignments without a model")
    func builtInNotesStayConservative() async throws {
        let transcript = """
        **[00:01] Priya:** Let's ship the smaller beta.
        **[00:08] Jordan:** I'll share the onboarding prototype by Thursday.
        **[00:15] Alex:** Who owns the support review?
        """
        let note = try await BuiltInMeetingSummarizer().summarize(.init(
            title: "Beta planning",
            attendees: [],
            transcriptMarkdown: transcript,
            userNotes: "Make sure Jordan's prototype is included in the follow-up.",
            style: .balanced
        ))
        #expect(note.summary.contains("transcript is ready"))
        #expect(note.decisions.isEmpty)
        #expect(note.actionItems.isEmpty)
        #expect(note.openQuestions.isEmpty)
    }

    @Test("An explicit remote summarizer is rendered without claiming local generation")
    func explicitRemoteSummary() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-remote-note-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"title":"Launch review","attendees":["Priya"]}"#.utf8)
            .write(to: dir.appendingPathComponent("meta.json"))

        try await NotePipeline.generate(
            sessionDir: dir,
            transcriptMarkdown: "**[00:01] Priya:** We approved the Friday launch.",
            summarizer: FixedRemoteSummarizer(),
            generatedLocally: false
        )

        let markdown = try String(contentsOf: dir.appendingPathComponent("note.md"), encoding: .utf8)
        #expect(markdown.contains("The team approved the launch plan."))
        #expect(markdown.contains("Generated with Venice AI · kimi-k3"))
        #expect(!markdown.contains("Generated locally with Venice"))
    }
}
