import Foundation

/// Human edits are authoritative and stored separately from replaceable AI output.
enum MeetingNotesEdits {
    static func read(from directory: URL) -> String? {
        try? String(contentsOf: directory.appendingPathComponent("meeting-notes.md"), encoding: .utf8)
    }

    static func save(_ text: String, to directory: URL) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent("meeting-notes.md"), options: .atomic)
    }

    /// Export the authoritative notes while leaving the original AI output available on disk.
    static func applying(to markdown: String, in directory: URL) -> String {
        guard let edits = read(from: directory) else { return markdown }
        return MeetingAnalysisEdits.replacingSections(in: markdown, edits: [("Meeting Notes", edits)])
    }
}

enum MeetingSummaryEdits {
    static func read(from directory: URL) -> String? {
        try? String(contentsOf: directory.appendingPathComponent("summary-edits.md"), encoding: .utf8)
    }

    static func save(_ text: String, to directory: URL) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent("summary-edits.md"), options: .atomic)
    }
}

enum MeetingAnalysisEdits {
    static func applying(to markdown: String, in directory: URL) -> String {
        var edits: [(String, String)] = []
        if let summary = MeetingSummaryEdits.read(from: directory) { edits.append(("Summary", summary)) }
        if let notes = MeetingNotesEdits.read(from: directory) { edits.append(("Meeting Notes", notes)) }
        return replacingSections(in: markdown, edits: edits)
    }

    static func replacingSections(in markdown: String, edits: [(String, String)]) -> String {
        let lines = markdown.components(separatedBy: "\n")
        // Locate all ranges in the original before inserting user text, which may itself contain headings.
        let replacements = edits.enumerated().map { order, edit in
            let heading = lines.firstIndex {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "## \(edit.0.lowercased())"
            }
            let start = heading ?? lines.firstIndex(of: "---") ?? lines.count
            let end = heading.map { index in
                lines.indices.dropFirst(index + 1).first { lines[$0].hasPrefix("## ") || lines[$0] == "---" }
                    ?? lines.count
            } ?? start
            return (start: start, end: end, order: order, text: ["## \(edit.0)", "", edit.1, ""])
        }
        var result = lines
        for replacement in replacements.sorted(by: { $0.start == $1.start ? $0.order > $1.order : $0.start > $1.start }) {
            result.replaceSubrange(replacement.start..<replacement.end, with: replacement.text)
        }
        return result.joined(separator: "\n")
    }
}
