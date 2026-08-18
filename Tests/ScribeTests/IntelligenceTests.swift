import Foundation
import Testing

@testable import Scribe

struct IntelligenceTests {
    @Test("Local Ask Scribe returns timestamped evidence without a provider")
    func localAnswerHasCitation() async throws {
        let meeting = MeetingRecord.demoMeetings().first!
        let answer = try await ScribeMeetingAssistant.answer(
            question: "What did we say about launch dependencies?",
            meetings: [meeting],
            settings: ScribeAISettings(
                provider: .local,
                model: "",
                baseURL: "",
                redactSensitive: true
            )
        )
        #expect(answer.contains("[01:18]"))
        #expect(answer.lowercased().contains("launch dependencies"))
    }

    @Test("Remote meeting context redacts common contact details by default")
    func redactsContactDetails() {
        var meeting = MeetingRecord.demoMeetings().first!
        meeting.transcript = [MeetingTranscriptLine(
            id: 0,
            startMilliseconds: 1_000,
            speaker: "YOU",
            text: "Email me at person@example.com or call 212-555-0199."
        )]
        let context = ScribeMeetingAssistant.contextText([meeting], redact: true)
        #expect(!context.contains("person@example.com"))
        #expect(!context.contains("212-555-0199"))
        #expect(context.contains("[REDACTED]"))
    }

    @Test("Follow-up drafts include captured decisions and actions")
    func draftsFollowUp() {
        let meeting = MeetingRecord.demoMeetings().first!
        let draft = ScribeFollowUpComposer.draft(kind: .recap, meeting: meeting)
        #expect(draft.contains("Subject: Q4 product planning"))
        #expect(draft.contains("Finalize beta scope"))
        #expect(draft.contains("Keep the beta focused"))
    }

    @Test("Workspace metadata remains ordinary local JSON")
    func savesWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var meeting = MeetingRecord.demoMeetings().first!
        meeting = MeetingRecord(
            id: root.path,
            directory: root,
            title: meeting.title,
            startedAt: meeting.startedAt,
            durationSeconds: meeting.durationSeconds,
            state: "complete",
            attendees: [],
            sourceBundleID: nil,
            summary: meeting.summary,
            decisions: meeting.decisions,
            actionItems: meeting.actionItems,
            openQuestions: meeting.openQuestions,
            transcript: meeting.transcript,
            userNotes: ""
        )
        let value = MeetingWorkspace(project: "Northstar", people: ["Maya"], tags: ["launch"])
        try MeetingWorkspaceStore.save(value, for: meeting)
        #expect(MeetingWorkspaceStore.read(from: root) == value)
    }
}
