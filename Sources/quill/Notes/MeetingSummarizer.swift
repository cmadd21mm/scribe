import Foundation

struct SummarizationRequest: Sendable {
    let title: String
    let attendees: [String]
    let transcriptMarkdown: String
}

struct StructuredMeetingNote: Codable, Equatable, Sendable {
    struct ActionItem: Codable, Equatable, Sendable {
        let task: String
        let owner: String?
        let due: String?
    }

    let summary: String
    let decisions: [String]
    let actionItems: [ActionItem]
    let openQuestions: [String]
}

protocol MeetingSummarizer: Sendable {
    var backendName: String { get }
    func summarize(_ request: SummarizationRequest) async throws -> StructuredMeetingNote
}

enum SummaryOutputParser {
    enum ParseError: Error, CustomStringConvertible {
        case noJSONObject
        case invalidJSON(Error)

        var description: String {
            switch self {
            case .noJSONObject: return "local model did not return a JSON object"
            case .invalidJSON(let error): return "local model returned invalid JSON: \(error)"
            }
        }
    }

    static func parse(_ output: String) throws -> StructuredMeetingNote {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"),
              start <= end else { throw ParseError.noJSONObject }
        let json = String(output[start...end])
        do {
            return try JSONDecoder().decode(StructuredMeetingNote.self, from: Data(json.utf8))
        } catch {
            throw ParseError.invalidJSON(error)
        }
    }
}
