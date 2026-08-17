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

    func run() async throws {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        let transcript = try String(
            contentsOf: dir.appendingPathComponent("transcript.md"),
            encoding: .utf8
        )
        try await NotePipeline.generate(sessionDir: dir, transcriptMarkdown: transcript)
        print("note ready at \(dir.appendingPathComponent("note.md").path)")
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
