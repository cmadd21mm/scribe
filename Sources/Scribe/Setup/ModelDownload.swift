import Foundation

/// A cancellable child process. Output goes to a temporary file so verbose
/// downloads cannot deadlock on a full pipe while the app waits for exit.
@MainActor
final class ModelDownload {
    private var process: Process?
    private var cancelled = false

    func start(model: LocalTranscriptionModel, completion: @escaping (String?) -> Void) {
        guard process == nil else { return }
        cancelled = false
        let child = Process()
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-download-\(UUID().uuidString).log")
        do {
            try Data().write(to: log)
            let output = try FileHandle(forWritingTo: log)
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["models", "download-transcription", "--model", model.rawValue]
            child.standardOutput = output
            child.standardError = output
            try child.run()
            process = child
            Task {
                let status = await Task.detached { child.waitUntilExit(); return child.terminationStatus }.value
                try? output.close()
                let detail = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: log)
                process = nil
                if cancelled {
                    completion("Download cancelled. You can retry whenever you’re ready.")
                } else if status != 0 || !model.isInstalled {
                    completion("The model couldn’t be installed. Check your connection and available storage, then retry. \(detail.suffix(500))")
                } else {
                    completion(nil)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: log)
            completion(error.localizedDescription)
        }
    }

    func cancel() {
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
}
