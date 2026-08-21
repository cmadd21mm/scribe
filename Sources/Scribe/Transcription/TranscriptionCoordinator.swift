import Foundation

/// Post-recording pipeline: a serial queue of session folders to transcribe.
/// mic.caf → "me", system.caf → "them"; each track's segments are shifted by
/// its start offset, merged by timestamp, and written as transcript.json
/// (canonical) plus transcript.md (readable). The filesystem is the queue —
/// `resumePending()` rescans at launch, so a crash or quit mid-transcription
/// just retries on next run. Failures append to the session's transcribe.log
/// and never block later jobs.
actor TranscriptionCoordinator {
    enum Status: Sendable {
        case idle
        case transcribing(session: String, queued: Int)
        case failed(session: String)
    }

    private var queue: [URL] = []
    private var draining = false
    private var engine: TranscriptionEngine?
    private var lastFailure: String?
    private var statusHandler: (@Sendable (Status) -> Void)?

    func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        statusHandler = handler
    }

    func processNow(_ sessionDir: URL) async throws {
        do {
            try await transcribe(sessionDir)
            await releaseEngine()
        } catch {
            await releaseEngine()
            throw error
        }
    }

    private func releaseEngine() async {
        await engine?.release()
        engine = nil
    }

    /// Queue a finished session. With transcription disabled, the local audio
    /// and metadata remain available and no post-processing process is run.
    func enqueue(_ sessionDir: URL) {
        guard Config.transcriptionEnabled() else { return }
        queue.append(sessionDir)
        drainIfIdle()
    }

    /// Scan the recordings root for sessions that finished (meta.json exists)
    /// but were never transcribed. Folder names sort chronologically, so
    /// oldest-first is a name sort.
    func resumePending(root: URL) {
        guard Config.transcriptionEnabled() else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return }

        let fm = FileManager.default
        let pending = entries
            .filter {
                Self.shouldResumeSession($0, fileManager: fm)
                    && !fm.fileExists(atPath: $0.appendingPathComponent("transcript.json").path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for dir in pending where !queue.contains(dir) {
            queue.append(dir)
        }
        if !pending.isEmpty {
            FileHandle.standardError.write(Data(
                "resuming \(pending.count) untranscribed session(s)\n".utf8
            ))
        }
        drainIfIdle()
    }

    /// Silent sessions are intentionally retained for troubleshooting but
    /// must not be re-enqueued every time Scribe launches. Older 0.2.14
    /// sessions did not have `has_usable_audio`, so recognize their two-track
    /// silence warning as well.
    static func shouldResumeSession(
        _ dir: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let metadataURL = dir.appendingPathComponent("meta.json")
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        if metadata["has_usable_audio"] as? Bool == false { return false }
        let warnings = Set(metadata["capture_warnings"] as? [String] ?? [])
        if warnings.contains("microphone") && warnings.contains("call audio") {
            return false
        }

        let files = metadata["files"] as? [String: String] ?? [:]
        return files.values.contains {
            fileManager.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    // MARK: -

    private func drainIfIdle() {
        guard !draining, !queue.isEmpty else { return }
        draining = true
        lastFailure = nil
        Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let dir = queue.removeFirst()
            publish(.transcribing(session: dir.lastPathComponent, queued: queue.count))
            do {
                try await transcribe(dir)
                notifyUser(title: "Scribe — transcript ready", body: dir.lastPathComponent)
            } catch {
                log(dir, "transcription failed: \(error)")
                lastFailure = dir.lastPathComponent
                notifyUser(
                    title: "Scribe — transcription failed",
                    body: "\(dir.lastPathComponent) — see transcribe.log"
                )
            }
        }
        await engine?.release()
        engine = nil
        publish(lastFailure.map { .failed(session: $0) } ?? .idle)
        draining = false
        // An enqueue that landed between the loop exiting and the release
        // finishing would otherwise sit until the next enqueue.
        drainIfIdle()
    }

    private func transcribe(_ dir: URL) async throws {
        let meta = try SessionMeta.read(from: dir)
        let engine = try await preparedEngine()

        var merged: [Transcript.Segment] = []
        for track in meta.tracks {
            let audio = dir.appendingPathComponent(track.file)
            guard FileManager.default.fileExists(atPath: audio.path) else {
                log(dir, "skipping missing track \(track.file)")
                continue
            }
            log(dir, "transcribing \(track.file) (\(engine.name))")
            // One bad track (empty, truncated) shouldn't cost us the other's
            // transcript — log it and keep going.
            let segments: [TranscriptSegment]
            do {
                segments = try await engine.transcribe(audio)
            } catch {
                log(dir, "skipping \(track.file): \(error)")
                continue
            }
            let offset = TimeInterval(track.offsetMs) / 1000
            merged += segments.map {
                Transcript.Segment(
                    speaker: track.speaker,
                    start_ms: Int(($0.start + offset) * 1000),
                    end_ms: Int(($0.end + offset) * 1000),
                    text: $0.text
                )
            }
        }
        merged.sort { $0.start_ms < $1.start_ms }
        merged = TranscriptEchoDeduplicator.removingCrossTrackEcho(from: merged)

        let transcript = Transcript(
            engine: engine.name,
            model: engine.model,
            created_at: ISO8601DateFormatter().string(from: Date()),
            segments: merged
        )
        try transcript.writeMarkdown(to: dir)
        let markdown = try String(
            contentsOf: dir.appendingPathComponent("transcript.md"),
            encoding: .utf8
        )
        try await NotePipeline.generate(sessionDir: dir, transcriptMarkdown: markdown)
        try transcript.writeCompletionMarker(to: dir)
        log(dir, "done — \(merged.count) segments")
    }

    private func preparedEngine() async throws -> TranscriptionEngine {
        if let engine { return engine }
        let configured = Config.transcriptionEngine()
        if configured != "parakeet" {
            FileHandle.standardError.write(Data(
                "warning: unknown transcription engine \"\(configured)\" — using parakeet\n".utf8
            ))
        }
        let engine = ParakeetEngine()
        try await engine.prepare()
        self.engine = engine
        return engine
    }

    private func log(_ dir: URL, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = dir.appendingPathComponent("transcribe.log")
        if let handle = FileHandle(forWritingAtPath: url.path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private func publish(_ status: Status) {
        statusHandler?(status)
    }
}

/// Speaker playback can leak into the microphone when the user records over
/// Mac speakers with voice processing disabled. Both recognizers then return
/// nearly the same sentence at the same moment. Prefer the clean system track
/// for long, strongly matching overlaps while preserving short acknowledgments
/// and genuine repetitions later in the conversation.
enum TranscriptEchoDeduplicator {
    static func removingCrossTrackEcho(
        from segments: [Transcript.Segment]
    ) -> [Transcript.Segment] {
        let remote = segments.filter { $0.speaker == "them" }
        return segments.filter { candidate in
            guard candidate.speaker == "me" else { return true }
            let candidateWords = words(candidate.text)
            guard candidateWords.count >= 4 else { return true }

            let isEcho = remote.contains { other in
                guard abs(other.start_ms - candidate.start_ms) <= 1_000,
                      max(other.start_ms, candidate.start_ms)
                        <= min(other.end_ms, candidate.end_ms) + 500
                else { return false }
                let otherWords = words(other.text)
                guard otherWords.count >= 4 else { return false }
                let shorter = min(candidateWords.count, otherWords.count)
                let longer = max(candidateWords.count, otherWords.count)
                guard Double(shorter) / Double(longer) >= 0.65 else { return false }
                let overlap = candidateWords.intersection(otherWords).count
                return Double(overlap) / Double(shorter) >= 0.8
            }
            return !isEcho
        }
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

/// The slice of meta.json the coordinator needs: which files exist, who they
/// represent, and how far each track started after the earliest one.
private struct SessionMeta {
    struct Track {
        let file: String
        let speaker: String
        let offsetMs: Int
    }

    let tracks: [Track]

    enum MetaError: Error, CustomStringConvertible {
        case unreadable(URL)

        var description: String {
            switch self {
            case .unreadable(let url): return "can't parse \(url.path)"
            }
        }
    }

    static func read(from dir: URL) throws -> SessionMeta {
        let url = dir.appendingPathComponent("meta.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let files = json["files"] as? [String: String]
        else { throw MetaError.unreadable(url) }

        // Sessions recorded before offsets were captured default to 0 —
        // tracks start within tens of milliseconds of each other anyway.
        let offsets = json["start_offset_ms"] as? [String: Int] ?? [:]
        var tracks: [Track] = []
        if let mic = files["mic"] {
            tracks.append(Track(file: mic, speaker: "me", offsetMs: offsets["mic"] ?? 0))
        }
        if let system = files["system"] {
            tracks.append(Track(file: system, speaker: "them", offsetMs: offsets["system"] ?? 0))
        }
        return SessionMeta(tracks: tracks)
    }
}

/// Canonical transcript. Property names are the JSON schema — this struct
/// exists to be serialized.
struct Transcript: Codable {
    struct Segment: Codable {
        let speaker: String
        let start_ms: Int
        let end_ms: Int
        let text: String
    }

    let engine: String
    let model: String
    let created_at: String
    let segments: [Segment]

    /// Render Markdown first, then write transcript.json as the durable
    /// completion marker. Both writes are atomic, so interrupted sessions are
    /// safely retried instead of being mistaken for complete transcripts.
    func write(to dir: URL) throws {
        try writeMarkdown(to: dir)
        try writeCompletionMarker(to: dir)
    }

    func writeMarkdown(to dir: URL) throws {
        let markdown = Data(rendered(title: dir.lastPathComponent).utf8)
        try markdown.write(
            to: dir.appendingPathComponent("transcript.md"),
            options: .atomic
        )
    }

    func writeCompletionMarker(to dir: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(self)
        try json
            .write(to: dir.appendingPathComponent("transcript.json"), options: .atomic)
    }

    private func rendered(title: String) -> String {
        var lines = ["# \(title)", "", "engine: \(engine) (\(model))", ""]
        for seg in segments {
            lines.append("**[\(Self.clock(seg.start_ms))] \(seg.speaker):** \(seg.text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func clock(_ ms: Int) -> String {
        let total = ms / 1000
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
