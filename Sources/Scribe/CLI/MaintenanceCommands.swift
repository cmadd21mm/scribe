import ArgumentParser
import Foundation

struct TranscribeSession: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe one local meeting folder and generate its note."
    )

    @Argument(help: "Meeting directory containing meta.json and audio tracks.")
    var directory: String

    func run() async throws {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        let coordinator = TranscriptionCoordinator()
        try await coordinator.processNow(dir)
        print("transcript and note ready in \(dir.path)")
    }
}

struct RegenerateNote: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Regenerate note.md from an existing local transcript."
    )

    @Argument(help: "Meeting directory containing transcript.md and meta.json.")
    var directory: String

    @Flag(name: .long, help: "Use the AI provider and model selected in Scribe Settings.")
    var useAI = false

    func run() async throws {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        let transcript = try String(
            contentsOf: dir.appendingPathComponent("transcript.md"),
            encoding: .utf8
        )
        let settings = Config.aiSettings()
        if useAI {
            guard settings.provider != .local else {
                throw ValidationError("Choose a remote AI provider in Scribe Settings first.")
            }
            try await NotePipeline.generate(
                sessionDir: dir,
                transcriptMarkdown: transcript,
                summarizer: ScribeRemoteMeetingSummarizer(settings: settings),
                generatedLocally: false
            )
        } else {
            try await NotePipeline.generate(sessionDir: dir, transcriptMarkdown: transcript)
        }
        print("note ready at \(dir.appendingPathComponent("note.md").path)")
    }
}

struct ConfigureAI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "configure-ai",
        abstract: "Select an AI provider and model without placing API keys in configuration files."
    )

    @Option(name: .long, help: "Provider: local, venice, openai, claude, xai, or custom.")
    var provider: String

    @Option(name: .long, help: "Provider model ID.")
    var model: String = ""

    func run() throws {
        guard let selected = ScribeAIProvider(rawValue: provider) else {
            throw ValidationError("Unknown AI provider '\(provider)'.")
        }
        try Config.update { configuration in
            let current = configuration.intelligence
            configuration.intelligence = .init(
                provider: selected.rawValue,
                model: model,
                baseURL: selected.defaultBaseURL,
                redactSensitive: current?.redactSensitive ?? true
            )
        }
        print("AI model set to \(selected.title) · \(model.isEmpty ? "not selected" : model)")
    }
}

struct SetMeetingSource: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-source",
        abstract: "Correct the displayed source for an existing local meeting."
    )

    @Argument(help: "Meeting directory containing meta.json.")
    var directory: String

    @Option(name: .long, help: "Source name, such as Google Meet, Zoom, or In person.")
    var name: String

    func run() throws {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try MeetingLibraryReader.setSourceName(name, for: dir)
        print("meeting source updated to \(name)")
    }
}

struct RecoverSessions: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recover",
        abstract: "Recover interrupted recordings under the configured root."
    )

    @Option(name: .long, help: "Override the configured recordings root.")
    var out: String?

    func run() throws {
        let root = Config.resolveRoot(cliOverride: out)
        let recovered = try SessionRecovery.recoverInterrupted(root: root)
        print("recovered \(recovered.count) interrupted recording(s)")
        for dir in recovered { print(dir.path) }
    }
}
