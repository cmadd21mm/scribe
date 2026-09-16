import Foundation
import Testing

@testable import Scribe

struct TranscriptionRenameTests {
    @Test("Renaming during model loading or either track preserves the full transcript",
          arguments: ["prepare", "mic.caf", "system.caf"])
    func renameDuringTranscription(phase: String) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scribe-rename-race-\(UUID())")
        let directory = root.appendingPathComponent("2026-09-08 1835 - Untitled meeting")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("""
        {"state":"complete","title":"Untitled meeting","started":"2026-09-08T22:35:22Z",
         "files":{"mic":"mic.caf","system":"system.caf"}}
        """.utf8).write(to: directory.appendingPathComponent("meta.json"))
        for name in ["mic.caf", "system.caf"] {
            try Data("fixture".utf8).write(to: directory.appendingPathComponent(name))
        }
        let meeting = try #require(MeetingLibraryReader.read(directory: directory))
        let engine = RenameTestEngine { stage in
            if stage == phase {
                _ = try MeetingLibraryReader.rename(meeting, to: "Customer conversation")
            }
        }
        let coordinator = TranscriptionCoordinator(makeEngine: { engine })
        try await coordinator.processNow(directory)

        let transcript = try JSONDecoder().decode(
            Transcript.self, from: Data(contentsOf: directory.appendingPathComponent("transcript.json"))
        )
        #expect(Set(transcript.segments.map(\.speaker)) == ["me", "them"])
        #expect(transcript.segments.count == 2)
        let markdown = try String(contentsOf: directory.appendingPathComponent("transcript.md"), encoding: .utf8)
        #expect(markdown.hasPrefix("# Customer conversation\n"))
        #expect(MeetingLibraryReader.read(directory: directory)?.title == "Customer conversation")
        #expect(try fm.contentsOfDirectory(atPath: root.path).count == 1)
    }
}

private actor RenameTestEngine: TranscriptionEngine {
    nonisolated let name = "test"
    nonisolated let model = "test"
    let onStage: @Sendable (String) throws -> Void

    init(onStage: @escaping @Sendable (String) throws -> Void) {
        self.onStage = onStage
    }

    func prepare() async throws { try onStage("prepare") }

    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        try onStage(audio.lastPathComponent)
        // Opening the path after the rename reproduces a model that has not
        // opened the track yet. No model download or real audio is needed.
        _ = try Data(contentsOf: audio)
        return [TranscriptSegment(start: 0, end: 1, text: audio.lastPathComponent)]
    }

    func release() async {}
}
