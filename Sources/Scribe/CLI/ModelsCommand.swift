import ArgumentParser
import FluidAudio
import Foundation

struct Models: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage explicitly downloaded local models.",
        subcommands: [DownloadTranscriptionModel.self]
    )
}

struct DownloadTranscriptionModel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download-transcription",
        abstract: "Explicitly download the Parakeet transcription model."
    )

    @Flag(name: .long, help: "Replace an existing cached model.")
    var force = false

    @Option(name: .long, help: "Model: parakeet-v2, parakeet-v3, or parakeet-110m.")
    var model: String = LocalTranscriptionModel.selected.rawValue

    func run() async throws {
        guard let selected = LocalTranscriptionModel(rawValue: model) else {
            throw ValidationError("Unknown model '\(model)'. Choose parakeet-v2, parakeet-v3, or parakeet-110m.")
        }
        let destination = try await AsrModels.download(force: force, version: selected.fluidVersion)
        print("transcription model ready at \(destination.path)")
    }
}
