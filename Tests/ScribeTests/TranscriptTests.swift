import Foundation
import Testing

@testable import Scribe

struct TranscriptTests {
    @Test("A failed Markdown write does not leave the completion marker")
    func failedMarkdownWriteDoesNotLeaveCompletionMarker() throws {
        let fileManager = FileManager.default
        let session = fileManager.temporaryDirectory
            .appendingPathComponent("scribe-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: session) }

        try fileManager.createDirectory(
            at: session.appendingPathComponent("transcript.md", isDirectory: true),
            withIntermediateDirectories: true
        )

        let transcript = Transcript(
            engine: "parakeet",
            model: "test-model",
            created_at: "2026-07-28T00:00:00Z",
            segments: []
        )

        do {
            try transcript.write(to: session)
            Issue.record("Expected writing transcript.md over a directory to fail")
        } catch {
            // Expected.
        }

        #expect(
            fileManager.fileExists(
                atPath: session.appendingPathComponent("transcript.json").path
            ) == false
        )
    }

    @Test("Silent retained sessions are not re-enqueued on launch")
    func silentSessionsDoNotResume() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("scribe-resume-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let current = try session(
            named: "current-silent",
            metadata: [
                "files": ["mic": "mic.caf"],
                "has_usable_audio": false,
            ],
            under: root
        )
        #expect(!TranscriptionCoordinator.shouldResumeSession(current))

        let legacy = try session(
            named: "legacy-silent",
            metadata: [
                "files": ["mic": "mic.caf", "system": "system.caf"],
                "capture_warnings": ["microphone", "call audio"],
            ],
            under: root
        )
        #expect(!TranscriptionCoordinator.shouldResumeSession(legacy))

        let usable = try session(
            named: "usable",
            metadata: [
                "files": ["mic": "mic.caf"],
                "has_usable_audio": true,
            ],
            under: root
        )
        #expect(TranscriptionCoordinator.shouldResumeSession(usable))
    }

    @Test("Overlapping speaker playback is removed from the microphone track")
    func removesCrossTrackEcho() {
        let segments = [
            segment("them", 1_000, 3_000, "Zoom Teams Google Meet and FaceTime use this capture path"),
            segment("me", 1_050, 3_050, "Zoom, Teams, Google Meet and FaceTime use this capture path."),
            segment("me", 4_000, 4_300, "Yes"),
        ]
        let result = TranscriptEchoDeduplicator.removingCrossTrackEcho(from: segments)
        #expect(result.map(\.speaker) == ["them", "me"])
        #expect(result.map(\.text) == [
            "Zoom Teams Google Meet and FaceTime use this capture path",
            "Yes",
        ])
    }

    @Test("A later deliberate repetition remains in the transcript")
    func preservesLaterRepetition() {
        let segments = [
            segment("them", 1_000, 2_000, "Please confirm the launch date tomorrow"),
            segment("me", 4_000, 5_000, "Please confirm the launch date tomorrow"),
        ]
        #expect(TranscriptEchoDeduplicator.removingCrossTrackEcho(from: segments).count == 2)
    }

    private func session(
        named name: String,
        metadata: [String: Any],
        under root: URL
    ) throws -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let files = metadata["files"] as? [String: String] {
            for file in files.values {
                try Data("audio".utf8).write(to: dir.appendingPathComponent(file))
            }
        }
        try JSONSerialization.data(withJSONObject: metadata).write(
            to: dir.appendingPathComponent("meta.json")
        )
        return dir
    }

    private func segment(
        _ speaker: String,
        _ start: Int,
        _ end: Int,
        _ text: String
    ) -> Transcript.Segment {
        Transcript.Segment(speaker: speaker, start_ms: start, end_ms: end, text: text)
    }
}
