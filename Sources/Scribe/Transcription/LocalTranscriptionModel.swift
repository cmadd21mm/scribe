import FluidAudio
import Foundation

enum LocalTranscriptionModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "parakeet-v2"
    case multilingual = "parakeet-v3"
    case compact = "parakeet-110m"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: return "Parakeet English"
        case .multilingual: return "Parakeet Multilingual"
        case .compact: return "Parakeet Compact"
        }
    }

    var detail: String {
        switch self {
        case .english: return "Best English accuracy · recommended"
        case .multilingual: return "25 European languages"
        case .compact: return "Fastest and lightest for everyday notes"
        }
    }

    var approximateSize: String {
        switch self {
        case .english, .multilingual: return "About 600 MB"
        case .compact: return "About 150 MB"
        }
    }

    var modelIdentifier: String {
        switch self {
        case .english: return "parakeet-tdt-0.6b-v2-coreml"
        case .multilingual: return "parakeet-tdt-0.6b-v3-coreml"
        case .compact: return "parakeet-tdt-ctc-110m-coreml"
        }
    }

    var fluidVersion: AsrModelVersion {
        switch self {
        case .english: return .v2
        case .multilingual: return .v3
        case .compact: return .tdtCtc110m
        }
    }

    var isInstalled: Bool {
        let cache = AsrModels.defaultCacheDirectory(for: fluidVersion)
        return AsrModels.modelsExist(at: cache, version: fluidVersion)
    }

    static var selected: LocalTranscriptionModel {
        LocalTranscriptionModel(rawValue: Config.transcriptionModelID()) ?? .english
    }
}
