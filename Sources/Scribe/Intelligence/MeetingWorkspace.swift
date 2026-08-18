import Foundation

struct MeetingWorkspace: Codable, Equatable, Hashable, Sendable {
    var project: String = ""
    var people: [String] = []
    var tags: [String] = []
}

enum MeetingWorkspaceStore {
    static func read(from directory: URL) -> MeetingWorkspace {
        let url = directory.appendingPathComponent("scribe-context.json")
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(MeetingWorkspace.self, from: data)
        else { return MeetingWorkspace() }
        return value
    }

    static func save(_ value: MeetingWorkspace, for meeting: MeetingRecord) throws {
        guard !meeting.isDemo else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(
            to: meeting.directory.appendingPathComponent("scribe-context.json"),
            options: .atomic
        )
    }
}

enum ScribeFollowUpKind: String, CaseIterable, Identifiable, Sendable {
    case recap = "Email recap"
    case status = "Status update"
    case agenda = "Next agenda"
    case tasks = "Task list"

    var id: String { rawValue }
}

enum ScribeFollowUpComposer {
    static func draft(kind: ScribeFollowUpKind, meeting: MeetingRecord) -> String {
        let actions = meeting.actionItems.map { "- \($0.text)" }
        let decisions = meeting.decisions.map { "- \($0)" }
        let questions = meeting.openQuestions.map { "- \($0)" }
        switch kind {
        case .recap:
            return """
            Subject: \(meeting.title) — recap and next steps

            Hi all,

            Thanks for the conversation. Here’s the short version:

            \(meeting.summary)

            Decisions
            \(decisions.isEmpty ? "- No explicit decisions captured." : decisions.joined(separator: "\n"))

            Next steps
            \(actions.isEmpty ? "- No action items captured." : actions.joined(separator: "\n"))

            Please reply if I missed anything.
            """
        case .status:
            return """
            \(meeting.title) — status

            Summary
            \(meeting.summary)

            Decisions
            \(decisions.isEmpty ? "- None captured." : decisions.joined(separator: "\n"))

            Actions
            \(actions.isEmpty ? "- None captured." : actions.joined(separator: "\n"))

            Open questions
            \(questions.isEmpty ? "- None captured." : questions.joined(separator: "\n"))
            """
        case .agenda:
            return """
            Next meeting: \(meeting.title)

            1. Review progress on prior actions
            \(actions.isEmpty ? "- No prior actions captured." : actions.joined(separator: "\n"))

            2. Resolve open questions
            \(questions.isEmpty ? "- No open questions captured." : questions.joined(separator: "\n"))

            3. Confirm decisions and owners
            """
        case .tasks:
            return actions.isEmpty ? "No action items were captured for \(meeting.title)." : actions.joined(separator: "\n")
        }
    }
}
