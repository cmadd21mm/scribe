import Foundation

struct LlamaCppSummarizer: MeetingSummarizer {
    enum BackendError: Error, CustomStringConvertible {
        case executableMissing(URL)
        case modelMissing(URL)
        case launchFailed(Error)
        case failed(Int32, String)

        var description: String {
            switch self {
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
            .appendingPathComponent("quill-summary-\(UUID().uuidString).txt")
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
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw BackendError.launchFailed(error)
        }
        process.waitUntilExit()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw BackendError.failed(
                process.terminationStatus,
                String(data: stderr, encoding: .utf8) ?? "unknown error"
            )
        }
        return try SummaryOutputParser.parse(String(data: stdout, encoding: .utf8) ?? "")
    }

    private func prompt(for request: SummarizationRequest) -> String {
        """
        You turn meeting transcripts into factual structured notes. Use only the transcript.
        Return exactly one JSON object and no Markdown fences, with this schema:
        {"summary":"string","decisions":["string"],"actionItems":[{"task":"string","owner":"string or null","due":"string or null"}],"openQuestions":["string"]}
        Do not invent decisions, owners, dates, or questions. Empty arrays are valid.

        Meeting: \(request.title)
        Attendees: \(request.attendees.joined(separator: ", "))

        Transcript:
        \(request.transcriptMarkdown)
        """
    }
}
