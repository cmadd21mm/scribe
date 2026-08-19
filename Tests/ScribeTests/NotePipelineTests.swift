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

    private struct FailingRemoteSummarizer: MeetingSummarizer {
        let backendName = "Venice AI · test"

        func summarize(_ request: SummarizationRequest) async throws -> StructuredMeetingNote {
            throw URLError(.timedOut)
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
        #expect(markdown.contains("## Summary\n\n_Not generated._"))
        #expect(markdown.contains("## Summary setup"))
        #expect(markdown.contains("no local summarization model"))
        #expect(markdown.contains("[transcript](transcript.md)"))
        #expect(markdown.contains("did not make a network call"))
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
        let log = try String(contentsOf: dir.appendingPathComponent("summary.log"), encoding: .utf8)
        #expect(markdown.contains("The team approved the launch plan."))
        #expect(markdown.contains("Generated with Venice AI · kimi-k3"))
        #expect(!markdown.contains("Generated locally with Venice"))
        #expect(log.contains("backend=Venice AI · kimi-k3"))
        #expect(log.contains("result=success"))
        #expect(!log.contains("We approved the Friday launch"))
    }

    @Test("A failed remote summary is logged without replacing the prior note")
    func failedRemoteSummaryKeepsPriorNote() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-failed-note-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"title":"Long interview"}"#.utf8)
            .write(to: dir.appendingPathComponent("meta.json"))
        let prior = "# Long interview\n\n## Summary\n\nPrior validated note."
        try Data(prior.utf8).write(to: dir.appendingPathComponent("note.md"))

        await #expect(throws: URLError.self) {
            try await NotePipeline.generate(
                sessionDir: dir,
                transcriptMarkdown: "**[00:01] Steve:** A long interview transcript.",
                summarizer: FailingRemoteSummarizer(),
                generatedLocally: false
            )
        }

        let note = try String(contentsOf: dir.appendingPathComponent("note.md"), encoding: .utf8)
        let log = try String(contentsOf: dir.appendingPathComponent("summary.log"), encoding: .utf8)
        #expect(note == prior)
        #expect(log.contains("result=failed"))
        #expect(log.contains("error="))
        #expect(!log.contains("long interview transcript"))
    }
}
