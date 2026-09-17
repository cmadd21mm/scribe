import Foundation

struct LlamaCppSummarizer: MeetingSummarizer {
    enum BackendError: Error, CustomStringConvertible {
        case executableMissing(URL)
        case modelMissing(URL)
        case launchFailed(Error)
        case failed(Int32, String)
        case timedOut

        var description: String {
            switch self {
            case .timedOut: return "The local model did not finish within 5 minutes. Try a smaller model or shorter context."
            case .executableMissing(let url): return "llama.cpp executable not found at \(url.path)"
            case .modelMissing(let url): return "local GGUF model not found at \(url.path)"
            case .launchFailed(let error): return "could not launch llama.cpp: \(error)"
            case .failed(let status, let message):
                return "llama.cpp exited \(status): \(message)"
            }
        }
    }

    let executable: URL
    let model: URL
    let predictionTokens: Int
    var backendName: String { "llama.cpp (\(model.lastPathComponent))" }

    func summarize(_ request: SummarizationRequest) async throws -> StructuredMeetingNote {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw BackendError.executableMissing(executable)
        }
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw BackendError.modelMissing(model)
        }

        let promptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-summary-\(UUID().uuidString).txt")
        try Data(prompt(for: request).utf8).write(to: promptURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: promptURL) }

        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "-m", model.path,
            "-f", promptURL.path,
            "-n", String(predictionTokens),
            "--temp", "0.2",
            "--no-display-prompt",
        ]
        // File-backed output avoids deadlocks when llama.cpp prints enough
        // progress to fill stderr before exiting.
        let stdoutURL = promptURL.appendingPathExtension("stdout")
        let stderrURL = promptURL.appendingPathExtension("stderr")
        try Data().write(to: stdoutURL)
        try Data().write(to: stderrURL)
        let output = try FileHandle(forWritingTo: stdoutURL)
        let errors = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? output.close()
            try? errors.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() }
        catch { throw BackendError.launchFailed(error) }
        let started = Date()
        while process.isRunning {
            if Task.isCancelled || Date().timeIntervalSince(started) > 300 {
                process.terminate()
                if Task.isCancelled { throw CancellationError() }
                throw BackendError.timedOut
            }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { process.terminate(); throw error }
        }
        let stdout = try Data(contentsOf: stdoutURL)
        let stderr = try Data(contentsOf: stderrURL)
        guard process.terminationStatus == 0 else {
            throw BackendError.failed(
                process.terminationStatus,
                String(data: stderr.suffix(4000), encoding: .utf8) ?? "unknown error"
            )
        }
        return try SummaryOutputParser.parse(String(data: stdout, encoding: .utf8) ?? "")
    }

    private func prompt(for request: SummarizationRequest) -> String {
        """
        You turn meeting transcripts into factual structured notes. Use only the transcript.
        Return exactly one JSON object and no Markdown fences, with this schema:
        \(MeetingNoteInstructions.schema)
        Do not invent decisions, owners, dates, or questions. Empty arrays are valid.
        \(MeetingNoteInstructions.discussionGuidance)
        Note style: \(request.style.title). \(request.style.guidance)

        Meeting: \(request.title)
        Attendees: \(request.attendees.joined(separator: ", "))
        The user's own notes are high-priority context. Preserve their emphasis,
        but do not treat a personal thought as a meeting decision unless the
        transcript supports it.

        User notes:
        \(request.userNotes.isEmpty ? "(none)" : request.userNotes)

        Transcript:
        \(request.transcriptMarkdown)
        """
    }
}
