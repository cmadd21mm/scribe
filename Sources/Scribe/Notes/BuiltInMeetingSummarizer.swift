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

        let summary = Self.summary(from: entries, style: request.style)
        let decisions = Self.unique(entries.compactMap { entry in
            Self.containsDecisionLanguage(entry.text) ? entry.text : nil
        }).prefix(6)
        let actions = Self.uniqueEntries(entries.filter { Self.containsActionLanguage($0.text) })
            .prefix(8)
            .map { entry in
                StructuredMeetingNote.ActionItem(
                    task: entry.text,
                    owner: Self.owner(for: entry.speaker),
                    due: Self.duePhrase(in: entry.text)
                )
            }
        let questions = Self.unique(entries.compactMap { entry in
            entry.text.contains("?") ? entry.text : nil
        }).prefix(6)

        return StructuredMeetingNote(
            summary: summary,
            decisions: Array(decisions),
            actionItems: Array(actions),
            openQuestions: Array(questions)
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

    private static func summary(from entries: [Entry], style: MeetingNoteStyle) -> String {
        let indexes: [Int]
        switch style {
        case .concise, .actionFocused:
            indexes = [0, entries.count - 1]
        case .balanced:
            indexes = [0, entries.count / 2, entries.count - 1]
        case .detailed:
            indexes = [0, entries.count / 4, entries.count / 2, (entries.count * 3) / 4, entries.count - 1]
        }
        let selected = indexes.reduce(into: [String]()) { result, index in
            let text = entries[index].text
            if !result.contains(text) { result.append(text) }
        }
        return selected.joined(separator: " ")
    }

    private static func containsDecisionLanguage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["decided", "agreed", "approved", "we'll", "we will", "let's", "going with"]
            .contains { lower.contains($0) }
    }

    private static func containsActionLanguage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return [
            "i'll", "i will", "we need to", "follow up", "send ", "share ",
            "confirm ", "schedule ", "finalize ", "action item", "by monday",
            "by tuesday", "by wednesday", "by thursday", "by friday",
        ].contains { lower.contains($0) }
    }

    private static func owner(for speaker: String) -> String? {
        switch speaker.lowercased() {
        case "me": return "You"
        case "them": return "Other participant"
        default: return speaker.capitalized
        }
    }

    private static func duePhrase(in text: String) -> String? {
        let pattern = #"\b(today|tomorrow|tonight|next week|by (?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let value = Range(match.range, in: text)
        else { return nil }
        return String(text[value])
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func uniqueEntries(_ values: [Entry]) -> [Entry] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.text.lowercased()).inserted }
    }
}
