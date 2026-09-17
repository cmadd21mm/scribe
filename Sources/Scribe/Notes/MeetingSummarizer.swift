import Foundation

enum MeetingNoteStyle: String, Codable, CaseIterable, Sendable {
    case concise
    case balanced
    case detailed
    case actionFocused = "action-focused"

    var title: String {
        switch self {
        case .concise: return "Concise"
        case .balanced: return "Balanced"
        case .detailed: return "Detailed"
        case .actionFocused: return "Action focused"
        }
    }

    var guidance: String {
        switch self {
        case .concise: return "Keep the summary to the essential outcome and next step."
        case .balanced: return "Balance context, decisions, action items, and open questions."
        case .detailed: return "Preserve important context and supporting discussion without inventing facts."
        case .actionFocused: return "Prioritize commitments, owners, due dates, and unresolved blockers."
        }
    }
}

struct SummarizationRequest: Sendable {
    let title: String
    let attendees: [String]
    let transcriptMarkdown: String
    let userNotes: String
    let style: MeetingNoteStyle
}

struct StructuredMeetingNote: Codable, Equatable, Sendable {
    struct DiscussionTopic: Codable, Equatable, Sendable {
        let topic: String
        let notes: String
    }

    struct ActionItem: Codable, Equatable, Sendable {
        let task: String
        let owner: String?
        let due: String?
    }

    let summary: String
    let decisions: [String]
    let actionItems: [ActionItem]
    let openQuestions: [String]
    // Older model responses remain readable without fabricating detailed notes.
    var meetingNotes: [DiscussionTopic]? = nil
}

enum MeetingNoteInstructions {
    static let outputTokens = 4_096
    static let schema = #"{"summary":"string","decisions":["string"],"actionItems":[{"task":"string","owner":"string or null","due":"string or null"}],"openQuestions":["string"],"meetingNotes":[{"topic":"string","notes":"string"}]}"#
    static let discussionGuidance = """
    Write meetingNotes as a briefing a thoughtful team member could send to their manager after attending.
    Organize the substantive discussion into topics, each with a short plain-text topic heading and
    readable prose notes (no Markdown headings or lists). Explain relevant background, options considered,
    the reasoning behind outcomes, concerns, disagreements, dependencies, and unresolved points when present.
    Preserve meaningful dates, numbers, and constraints. Attribute views only when the source is clear.
    Distinguish proposals from decisions and uncertainty from agreement. Do not invent consensus, rationale,
    facts, or topics. Personal notes provide emphasis, but are not evidence of what participants agreed to.
    Keep the summary brief; meetingNotes should add useful detail rather than repeat the summary or task lists.
    Scale detail to the actual discussion, without padding short meetings. An empty meetingNotes array is
    appropriate when the supplied material contains no substantive discussion.
    """
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
