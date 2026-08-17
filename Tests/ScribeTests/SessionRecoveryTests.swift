import Foundation
import Testing

@testable import Scribe

struct SessionRecoveryTests {
    @Test("Recovery finds an interrupted session and makes it transcribable")
    func recoversInterruptedMetadata() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("2026-01-01 1000 - Test", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: dir.appendingPathComponent("mic.caf"))
        let metadata: [String: Any] = [
            "schema_version": 1,
            "state": "recording",
            "started": "2026-01-01T10:00:00Z",
            "title": "Test",
            "files": ["mic": "mic.caf", "system": "system.caf"],
        ]
        try JSONSerialization.data(withJSONObject: metadata).write(
            to: dir.appendingPathComponent("meta.json")
        )

        let now = ISO8601DateFormatter().date(from: "2026-01-01T10:05:00Z")!
        let recoveredPaths = try SessionRecovery.recoverInterrupted(root: root, now: now)
            .map { $0.resolvingSymlinksInPath().path }
        #expect(recoveredPaths == [dir.resolvingSymlinksInPath().path])
        let recovered = try JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appendingPathComponent("meta.json"))
        ) as? [String: Any]
        #expect(recovered?["state"] as? String == "interrupted")
        #expect(recovered?["duration_seconds"] as? Int == 300)
        #expect((recovered?["files"] as? [String: String]) == ["mic": "mic.caf"])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("note.md").path))
    }

    @Test("Completed and audio-free folders are not recovery candidates")
    func ignoresNonInterruptedFolders() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let complete = root.appendingPathComponent("complete", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: complete, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data().write(to: complete.appendingPathComponent("system.caf"))
        try JSONSerialization.data(withJSONObject: ["state": "complete"]).write(
            to: complete.appendingPathComponent("meta.json")
        )
        #expect(SessionRecovery.interruptedDirectories(root: root).isEmpty)
    }

    @Test("Disk policy rejects values below the configured reserve")
    func diskSpacePolicy() {
        #expect(DiskSpacePolicy.hasEnoughSpace(availableBytes: 2_000, minimumBytes: 1_000))
        #expect(!DiskSpacePolicy.hasEnoughSpace(availableBytes: 999, minimumBytes: 1_000))
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
