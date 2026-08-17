import Foundation
import Testing

@testable import quill

struct NotePipelineTests {
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
}
