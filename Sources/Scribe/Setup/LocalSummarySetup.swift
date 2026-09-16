import Foundation

enum LocalSummarySetup {
    struct InvalidFiles: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func configuration(executable: String, model: String) throws -> ScribeConfiguration.Summarization {
        let executable = Config.expandPath(executable.trimmingCharacters(in: .whitespacesAndNewlines))
        let model = Config.expandPath(model.trimmingCharacters(in: .whitespacesAndNewlines))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: executable, isDirectory: &isDirectory),
              !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: executable) else {
            throw InvalidFiles(message: "Choose an executable llama.cpp file on this Mac.")
        }
        guard FileManager.default.fileExists(atPath: model, isDirectory: &isDirectory),
              !isDirectory.boolValue, FileManager.default.isReadableFile(atPath: model),
              URL(fileURLWithPath: model).pathExtension.lowercased() == "gguf" else {
            throw InvalidFiles(message: "Choose a readable GGUF summary model file.")
        }
        return .init(backend: "llama.cpp", executable: executable, modelPath: model, predictionTokens: 1200)
    }
}
