import Foundation
import Testing

@testable import Scribe

struct IntelligenceTests {
    @Test("Remote AI requests allow for variable provider latency")
    func remoteRequestDeadline() {
        #expect(ScribeRemoteAIClient.requestTimeoutSeconds == 120)
    }

    @Test("Venice Ask requests disable slow reasoning and web search")
    func responsiveVeniceAskBody() throws {
        let body = ScribeRemoteAIClient.openAICompatibleBody(
            prompt: "What did we decide?",
            settings: ScribeAISettings(
                provider: .venice,
                model: "kimi-k3-fast-api",
                baseURL: "",
                redactSensitive: true
            ),
            maxTokens: 800,
            structuredMeetingNote: false
        )
        let parameters = try #require(body["venice_parameters"] as? [String: Any])
        #expect(parameters["disable_thinking"] as? Bool == true)
        #expect(parameters["enable_web_search"] as? String == "off")
        #expect(parameters["include_venice_system_prompt"] as? Bool == false)
        #expect(body["response_format"] == nil)
    }

    @Test("Kimi K3 is available immediately even before Venice catalog refresh")
    func kimiK3Fallback() {
        let models = ScribeAIModelCatalog.veniceFallbackModels
        #expect(models.first?.id == "kimi-k3-fast-api")
        #expect(models.first?.isRecommended == true)
        #expect(models.contains { $0.id == "kimi-k3" })
    }

    @Test("Venice model discovery uses the fast public catalog with a short deadline")
    func veniceModelRequest() throws {
        let request = try ScribeAIModelCatalog.modelListRequest(
            provider: .venice,
            baseURL: "",
            apiKey: "secret"
        )
        #expect(request.url?.absoluteString == "https://api.venice.ai/api/v1/models?type=text")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.timeoutInterval == 8)
    }

    @Test("Venice model discovery can retry with authentication if its catalog requires it")
    func authenticatedVeniceModelRequest() throws {
        let request = try ScribeAIModelCatalog.modelListRequest(
            provider: .venice,
            baseURL: "",
            apiKey: "secret",
            authenticateVenice: true
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test("Venice model catalog keeps text models and friendly names")
    func parsesVeniceModels() throws {
        let data = Data(#"""
        {"data":[
          {"id":"venice-large","type":"text","model_spec":{"name":"Venice Large","description":"Best quality","traits":["default"]}},
          {"id":"venice-image","type":"image","model_spec":{"name":"Venice Image"}}
        ]}
        """#.utf8)
        let models = try ScribeAIModelCatalog.parse(data: data, provider: .venice)
        #expect(models.map(\.id) == ["venice-large"])
        #expect(models.first?.title == "Venice Large")
        #expect(models.first?.isRecommended == true)
    }

    @Test("Claude model catalog uses provider display names")
    func parsesClaudeModels() throws {
        let data = Data(#"""
        {"data":[{"id":"claude-example-20260818","display_name":"Claude Example"}]}
        """#.utf8)
        let models = try ScribeAIModelCatalog.parse(data: data, provider: .claude)
        #expect(models.first?.id == "claude-example-20260818")
        #expect(models.first?.title == "Claude Example")
    }

    @Test("xAI model catalog reads language-model aliases")
    func parsesXAIModels() throws {
        let data = Data(#"""
        {"models":[{"id":"grok-example","aliases":["grok-latest"]}]}
        """#.utf8)
        let models = try ScribeAIModelCatalog.parse(data: data, provider: .xAI)
        #expect(models.first?.id == "grok-example")
        #expect(models.first?.detail.contains("grok-latest") == true)
    }

    @Test("OpenAI model catalog hides models that cannot answer chat questions")
    func filtersOpenAIModels() throws {
        let data = Data(#"""
        {"data":[
          {"id":"gpt-example"},
          {"id":"davinci-002"},
          {"id":"text-embedding-example"},
          {"id":"image-example"},
          {"id":"whisper-example"}
        ]}
        """#.utf8)
        let models = try ScribeAIModelCatalog.parse(data: data, provider: .openAI)
        #expect(models.map(\.id) == ["gpt-example"])
    }

    @Test("OpenAI model catalog prefers a current general model when available")
    func prefersGeneralOpenAIModel() throws {
        let options = [
            ScribeAIModelOption(id: "gpt-4.1-mini", title: "gpt-4.1-mini", detail: "OpenAI", isRecommended: false),
            ScribeAIModelOption(id: "gpt-5", title: "gpt-5", detail: "OpenAI", isRecommended: false),
        ]
        #expect(ScribeAIModelCatalog.preferredModel(from: options, provider: .openAI)?.id == "gpt-5")
    }

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
