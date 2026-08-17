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

    func run() async throws {
        let destination = try await AsrModels.download(force: force, version: .v2)
        print("transcription model ready at \(destination.path)")
    }
}
