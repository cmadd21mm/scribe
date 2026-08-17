import Foundation

enum SessionRecovery {
    enum RecoveryError: Error {
        case invalidMetadata(URL)
    }

    static func interruptedDirectories(root: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.filter { dir in
            let hasAudio = ["mic.caf", "system.caf"].contains {
                FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
            }
            guard hasAudio else { return false }
            let metadataURL = dir.appendingPathComponent("meta.json")
            guard FileManager.default.fileExists(atPath: metadataURL.path) else { return true }
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return true }
            return metadata["state"] as? String == "recording"
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @discardableResult
    static func recoverInterrupted(root: URL, now: Date = Date()) throws -> [URL] {
        let iso = ISO8601DateFormatter()
        var recovered: [URL] = []
        for dir in interruptedDirectories(root: root) {
            let metadataURL = dir.appendingPathComponent("meta.json")
            var metadata: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                let data = try Data(contentsOf: metadataURL)
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { throw RecoveryError.invalidMetadata(metadataURL) }
                metadata = parsed
            }

            let files = ["mic", "system"].reduce(into: [String: String]()) { result, name in
                let filename = "\(name).caf"
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent(filename).path) {
                    result[name] = filename
                }
            }
            let started = metadata["started"] as? String ?? inferredStart(for: dir, iso: iso)
            let startedDate = iso.date(from: started) ?? now
            metadata["schema_version"] = metadata["schema_version"] ?? 1
            metadata["state"] = "interrupted"
            metadata["started"] = started
            metadata["ended"] = iso.string(from: now)
            metadata["recovered_at"] = iso.string(from: now)
            metadata["duration_seconds"] = max(0, Int(now.timeIntervalSince(startedDate)))
            metadata["title"] = metadata["title"] ?? dir.lastPathComponent
            metadata["attendees"] = metadata["attendees"] ?? []
            metadata["files"] = files
            metadata["start_offset_ms"] = metadata["start_offset_ms"]
                ?? ["mic": 0, "system": 0]

            let data = try JSONSerialization.data(
                withJSONObject: metadata,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: metadataURL, options: .atomic)
            if !FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("note.md").path
            ) {
                let title = metadata["title"] as? String ?? dir.lastPathComponent
                let note = "# \(title)\n\n_Interrupted recording recovered locally; transcription is pending._\n"
                try Data(note.utf8).write(
                    to: dir.appendingPathComponent("note.md"),
                    options: .atomic
                )
            }
            recovered.append(dir)
        }
        return recovered
    }

    private static func inferredStart(for dir: URL, iso: ISO8601DateFormatter) -> String {
        let values = try? dir.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return iso.string(from: values?.creationDate ?? values?.contentModificationDate ?? Date())
    }
}
