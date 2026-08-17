import Foundation

struct QuillConfiguration: Codable, Equatable, Sendable {
    struct Transcription: Codable, Equatable, Sendable {
        var enabled: Bool? = nil
        var engine: String? = nil
    }

    struct Summarization: Codable, Equatable, Sendable {
        var backend: String? = nil
        var executable: String? = nil
        var modelPath: String? = nil
        var predictionTokens: Int? = nil

        enum CodingKeys: String, CodingKey {
            case backend, executable
            case modelPath = "model_path"
            case predictionTokens = "prediction_tokens"
        }
    }

    var recordingsDir: String? = nil
    var transcription: Transcription? = nil
    var summarization: Summarization? = nil
    var micVoiceProcessing: Bool? = nil
    var callApps: [String]? = nil
    var callPromptDelaySeconds: Double? = nil
    var callEndDelaySeconds: Double? = nil
    var minimumFreeDiskGB: Double? = nil
    var promptForCalls: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case recordingsDir = "recordings_dir"
        case transcription, summarization
        case micVoiceProcessing = "mic_voice_processing"
        case callApps = "call_apps"
        case callPromptDelaySeconds = "call_prompt_delay_seconds"
        case callEndDelaySeconds = "call_end_delay_seconds"
        case minimumFreeDiskGB = "minimum_free_disk_gb"
        case promptForCalls = "prompt_for_calls"
    }
}

enum Config {
    enum LocalSummarizerConfiguration {
        case available(any MeetingSummarizer)
        case unavailable(String)
    }

    static let defaultCallAppBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.tinyspeck.slackmacgap",
        "com.apple.FaceTime",
        "com.hnc.Discord",
        "com.cisco.webexmeetingsapp",
        "Cisco-Systems.Spark",
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
    ]

    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/scribe/config.json")

    static let legacyPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/quill/config.json")

    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Recordings", isDirectory: true)

    static func parse(_ data: Data) throws -> QuillConfiguration {
        try JSONDecoder().decode(QuillConfiguration.self, from: data)
    }

    static func recordingsDir() -> URL? {
        guard let dir = load()?.recordingsDir, !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: expand(dir), isDirectory: true)
    }

    static func transcriptionEnabled() -> Bool {
        load()?.transcription?.enabled ?? true
    }

    static func transcriptionEngine() -> String {
        load()?.transcription?.engine ?? "parakeet"
    }

    static func micVoiceProcessing() -> Bool {
        load()?.micVoiceProcessing ?? false
    }

    static func callAppBundleIDs() -> Set<String> {
        guard let configured = load()?.callApps else { return defaultCallAppBundleIDs }
        return Set(configured.filter { !$0.isEmpty })
    }

    static func callPromptDelay() -> TimeInterval {
        max(0, load()?.callPromptDelaySeconds ?? 8)
    }

    static func callEndDelay() -> TimeInterval {
        max(0, load()?.callEndDelaySeconds ?? 10)
    }

    static func promptForCalls() -> Bool {
        load()?.promptForCalls ?? true
    }

    static func minimumFreeDiskBytes() -> Int64 {
        let gigabytes = max(0, load()?.minimumFreeDiskGB ?? 2)
        return Int64(gigabytes * 1_000_000_000)
    }

    static func localSummarizer() -> LocalSummarizerConfiguration {
        guard let summary = load()?.summarization else {
            return .unavailable("no local summarization model is configured")
        }
        guard summary.backend == "llama.cpp" else {
            return .unavailable("summarization.backend must be llama.cpp")
        }
        guard let executablePath = summary.executable,
              let modelPath = summary.modelPath else {
            return .unavailable("llama.cpp executable and model_path must be configured")
        }
        let executable = URL(fileURLWithPath: expand(executablePath))
        let model = URL(fileURLWithPath: expand(modelPath))
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return .unavailable("llama.cpp executable was not found at \(executable.path)")
        }
        guard FileManager.default.fileExists(atPath: model.path) else {
            return .unavailable("local GGUF model was not found at \(model.path)")
        }
        return .available(LlamaCppSummarizer(
            executable: executable,
            model: model,
            predictionTokens: summary.predictionTokens ?? 1_200
        ))
    }

    static func resolveRoot(cliOverride: String?) -> URL {
        if let cliOverride {
            return URL(fileURLWithPath: expand(cliOverride), isDirectory: true)
        }
        return recordingsDir() ?? defaultRoot
    }

    static func expandPath(_ value: String) -> String {
        expand(value)
    }

    static func current() -> QuillConfiguration {
        load() ?? QuillConfiguration()
    }

    static func update(_ change: (inout QuillConfiguration) -> Void) throws {
        var configuration = current()
        change(&configuration)
        try save(configuration)
    }

    static func save(_ configuration: QuillConfiguration) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: path, options: .atomic)
    }

    private static func load() -> QuillConfiguration? {
        let source: URL
        if FileManager.default.fileExists(atPath: path.path) {
            source = path
        } else if FileManager.default.fileExists(atPath: legacyPath.path) {
            source = legacyPath
        } else {
            return nil
        }
        do {
            return try parse(Data(contentsOf: source))
        } catch {
            FileHandle.standardError.write(Data(
                "warning: \(source.path) is invalid (\(error)) — using defaults\n".utf8
            ))
            return nil
        }
    }

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
