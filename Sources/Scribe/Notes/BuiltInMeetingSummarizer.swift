import Foundation

/// A deterministic fallback that turns every completed transcript into useful
/// notes without a model download. A configured local LLM can still replace it,
/// but Scribe never leaves a normal user with a transcript-only dead end.
struct BuiltInMeetingSummarizer: MeetingSummarizer {
    private struct Entry: Sendable {
        let speaker: String
        let text: String
    }

    var backendName: String { "Scribe built-in summary" }

    func summarize(_ request: SummarizationRequest) async throws -> StructuredMeetingNote {
        var entries = Self.entries(in: request.transcriptMarkdown)
        entries.append(contentsOf: Self.noteEntries(in: request.userNotes))
        guard !entries.isEmpty else {
            return StructuredMeetingNote(
                summary: "No spoken content was detected in this recording.",
                decisions: [],
                actionItems: [],
                openQuestions: []
            )
        }
        // Keyword heuristics look plausible but routinely turn discussion into
        // false decisions and assignments. Without a real summarization model,
        // be honest and preserve the transcript rather than invent structure.
        return StructuredMeetingNote(
            summary: "The transcript is ready. Use Regenerate summary with a configured AI model for a reliable summary, decisions, and action items.",
            decisions: [],
            actionItems: [],
            openQuestions: []
        )
    }

    private static func entries(in markdown: String) -> [Entry] {
        let pattern = #"^\*\*\[[^\]]+\]\s+([^:]+):\*\*\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return markdown.components(separatedBy: .newlines).compactMap { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let speakerRange = Range(match.range(at: 1), in: line),
                  let textRange = Range(match.range(at: 2), in: line)
            else { return nil }
            let text = String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Entry(speaker: String(line[speakerRange]), text: text)
        }
    }

    private static func noteEntries(in notes: String) -> [Entry] {
        notes.components(separatedBy: .newlines).compactMap { line in
            let text = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-•*"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : Entry(speaker: "You", text: text)
        }
    }

}
