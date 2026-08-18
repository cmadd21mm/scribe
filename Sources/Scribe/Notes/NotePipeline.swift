import Foundation

enum NoteRenderer {
    static func render(
        context: MeetingContext,
        note: StructuredMeetingNote,
        backendName: String,
        generatedLocally: Bool = true
    ) -> String {
        let attendees = context.attendees.isEmpty
            ? "_No calendar attendees available_"
            : context.attendees.map { "- \($0)" }.joined(separator: "\n")
        return """
        # \(context.title)

        ## Attendees

        \(attendees)

        ## Summary

        \(note.summary)

        ## Decisions

        \(list(note.decisions))

        ## Action items

        \(actionList(note.actionItems))

        ## Open questions

        \(list(note.openQuestions))

        ---

        _\(generatedLocally ? "Generated locally with" : "Generated with") \(backendName). See [transcript](transcript.md)._
        """
    }

    static func unavailable(context: MeetingContext, reason: String) -> String {
        let attendees = context.attendees.isEmpty
            ? "_No calendar attendees available_"
            : context.attendees.map { "- \($0)" }.joined(separator: "\n")
        return """
        # \(context.title)

        ## Attendees

        \(attendees)

        ## Summary

        > Structured notes were not generated: \(reason)

        ## Decisions

        _Not generated._

        ## Action items

        _Not generated._

        ## Open questions

        _Not generated._

        ---

        _The local [transcript](transcript.md) is available. Scribe did not make a network call._
        """
    }

    private static func list(_ values: [String]) -> String {
        values.isEmpty ? "_None identified._" : values.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func actionList(_ values: [StructuredMeetingNote.ActionItem]) -> String {
        guard !values.isEmpty else { return "_None identified._" }
        return values.map { item in
            let owner = item.owner.map { " — **Owner:** \($0)" } ?? ""
            let due = item.due.map { " — **Due:** \($0)" } ?? ""
            return "- [ ] \(item.task)\(owner)\(due)"
        }.joined(separator: "\n")
    }
}

enum NotePipeline {
    static func generate(
        sessionDir: URL,
        transcriptMarkdown: String,
        summarizer explicitSummarizer: (any MeetingSummarizer)? = nil,
        generatedLocally: Bool = true
    ) async throws {
        let context = readContext(from: sessionDir)
        let userNotes = (try? String(
            contentsOf: sessionDir.appendingPathComponent("user-notes.md"),
            encoding: .utf8
        )) ?? ""
        let rendered: String
        if let explicitSummarizer {
            let note = try await explicitSummarizer.summarize(SummarizationRequest(
                title: context.title,
                attendees: context.attendees,
                transcriptMarkdown: transcriptMarkdown,
                userNotes: userNotes,
                style: Config.noteStyle()
            ))
            rendered = NoteRenderer.render(
                context: context,
                note: note,
                backendName: explicitSummarizer.backendName,
                generatedLocally: generatedLocally
            )
            try Data(rendered.utf8).write(
                to: sessionDir.appendingPathComponent("note.md"),
                options: .atomic
            )
            return
        }
        switch Config.localSummarizer() {
        case .available(let summarizer):
            do {
                let note = try await summarizer.summarize(SummarizationRequest(
                    title: context.title,
                    attendees: context.attendees,
                    transcriptMarkdown: transcriptMarkdown,
                    userNotes: userNotes,
                    style: Config.noteStyle()
                ))
                rendered = NoteRenderer.render(
                    context: context,
                    note: note,
                    backendName: summarizer.backendName
                )
            } catch {
                let fallback = BuiltInMeetingSummarizer()
                let note = try await fallback.summarize(SummarizationRequest(
                    title: context.title,
                    attendees: context.attendees,
                    transcriptMarkdown: transcriptMarkdown,
                    userNotes: userNotes,
                    style: Config.noteStyle()
                ))
                rendered = NoteRenderer.render(
                    context: context,
                    note: note,
                    backendName: fallback.backendName
                )
            }
        case .unavailable(let reason):
            rendered = NoteRenderer.unavailable(context: context, reason: reason)
        }
        try Data(rendered.utf8).write(
            to: sessionDir.appendingPathComponent("note.md"),
            options: .atomic
        )
    }

    private static func readContext(from dir: URL) -> MeetingContext {
        let metadataURL = dir.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .fallback(title: dir.lastPathComponent, sourceBundleID: nil) }
        return MeetingContext(
            title: metadata["title"] as? String ?? dir.lastPathComponent,
            attendees: metadata["attendees"] as? [String] ?? [],
            calendarEventID: metadata["calendar_event_id"] as? String,
            sourceBundleID: metadata["source_bundle_id"] as? String
        )
    }
}
