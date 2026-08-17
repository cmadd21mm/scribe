import SwiftUI

struct ScribeAppView: View {
    @ObservedObject var model: ScribeAppModel

    var body: some View {
        HStack(spacing: 0) {
            MeetingSidebar(model: model)
                .frame(width: 400)
            Rectangle()
                .fill(ScribeTheme.divider)
                .frame(width: 1)
            Group {
                if let meeting = model.selectedMeeting {
                    MeetingDetail(model: model, meeting: meeting)
                } else {
                    EmptyLibrary(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ScribeTheme.paper)
        }
        .frame(minWidth: 1_040, minHeight: 700)
        .background(ScribeTheme.paper)
        .sheet(isPresented: $model.showSettings) {
            ScribeSettingsView(model: model)
        }
        .sheet(isPresented: $model.showOnboarding) {
            ScribeOnboardingView(model: model)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $model.showNotesEditor) {
            if let meeting = model.selectedMeeting {
                MeetingNotesEditor(model: model, meeting: meeting)
            }
        }
        .sheet(isPresented: $model.showRenameEditor) {
            if let meeting = model.selectedMeeting {
                MeetingRenameEditor(model: model, meeting: meeting)
            }
        }
        .confirmationDialog(
            "Move this meeting to Trash?",
            isPresented: $model.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                model.moveSelectedMeetingToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recording, transcript, and notes can be recovered from the Mac Trash.")
        }
        .alert(
            "Scribe",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

private struct MeetingSection: Identifiable {
    let id: String
    let meetings: [MeetingRecord]
}

private struct MeetingSidebar: View {
    @ObservedObject var model: ScribeAppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                ScribeBrand()
                    .padding(.leading, 70)
                    .padding(.top, 54)

                ScribeSectionDivider()

                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .medium))
                    Text("All Meetings")
                        .font(ScribeTheme.sans(14, weight: .medium))
                    Spacer()
                    Text("\(model.meetings.count)")
                        .font(ScribeTheme.sans(11, weight: .medium))
                        .foregroundStyle(ScribeTheme.faintInk)
                }
                .foregroundStyle(ScribeTheme.ink)
                .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ScribeTheme.faintInk)
                    TextField("Search every note", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(ScribeTheme.sans(13))
                    if !model.searchText.isEmpty {
                        Button {
                            model.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .scribePointer()
                        .foregroundStyle(ScribeTheme.faintInk)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(ScribeTheme.divider, lineWidth: 1)
                )
                .padding(.horizontal, 18)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if sections.isEmpty {
                        Text("No meetings match your search.")
                            .font(ScribeTheme.sans(13))
                            .foregroundStyle(ScribeTheme.mutedInk)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.id)
                                .font(ScribeTheme.sans(11, weight: .semibold))
                                .foregroundStyle(ScribeTheme.mutedInk)
                                .padding(.horizontal, 20)
                            ForEach(section.meetings) { meeting in
                                MeetingSidebarRow(
                                    meeting: meeting,
                                    selected: model.selectedMeetingID == meeting.id,
                                    onRename: {
                                        model.selectedMeetingID = meeting.id
                                        model.showRenameEditor = true
                                    },
                                    onDelete: {
                                        model.selectedMeetingID = meeting.id
                                        model.showDeleteConfirmation = true
                                    }
                                ) {
                                    model.selectedMeetingID = meeting.id
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 20)
            }

            ScribeSectionDivider()
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 17))
                    .foregroundStyle(ScribeTheme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved on this Mac")
                        .font(ScribeTheme.sans(12, weight: .medium))
                        .foregroundStyle(ScribeTheme.ink)
                    Text("Your notes never leave this device.")
                        .font(ScribeTheme.sans(10))
                        .foregroundStyle(ScribeTheme.faintInk)
                }
                Spacer()
                Button {
                    model.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .scribePointer()
                .foregroundStyle(ScribeTheme.ink)
                .help("Settings")
            }
            .padding(.horizontal, 20)
            .frame(height: 76)
        }
        .background(ScribeTheme.sidebar)
    }

    private var sections: [MeetingSection] {
        let calendar = Calendar.current
        let now = Date()
        let groups: [(String, (MeetingRecord) -> Bool)] = [
            ("Today", { calendar.isDateInToday($0.startedAt) }),
            ("Yesterday", { calendar.isDateInYesterday($0.startedAt) }),
            ("Last 7 Days", { now.timeIntervalSince($0.startedAt) < 7 * 86_400 }),
            ("Earlier", { _ in true }),
        ]
        var remaining = model.filteredMeetings
        return groups.compactMap { name, matches in
            let values = remaining.filter(matches)
            remaining.removeAll { candidate in values.contains(where: { $0.id == candidate.id }) }
            return values.isEmpty ? nil : MeetingSection(id: name, meetings: values)
        }
    }
}

private struct MeetingSidebarRow: View {
    let meeting: MeetingRecord
    let selected: Bool
    let onRename: () -> Void
    let onDelete: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(selected ? ScribeTheme.coral : Color.clear)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(ScribeTheme.serif(15, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(ScribeTheme.ink)
                    Text(Self.day.string(from: meeting.startedAt))
                        .font(ScribeTheme.sans(11))
                        .foregroundStyle(ScribeTheme.mutedInk)
                    HStack(spacing: 7) {
                        Text(Self.time.string(from: meeting.startedAt))
                        Text("•")
                        Text(Self.duration(meeting.durationSeconds))
                    }
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.faintInk)
                }
                .padding(.leading, 16)
                Spacer()
                if meeting.state == "recording" {
                    Circle()
                        .fill(ScribeTheme.coral)
                        .frame(width: 8, height: 8)
                } else if meeting.hasTranscript {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(ScribeTheme.ink)
                }
            }
            .padding(.trailing, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? ScribeTheme.selection.opacity(0.72) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .scribePointer()
        .padding(.horizontal, 14)
        .contextMenu {
            Button("Rename Meeting…", systemImage: "pencil", action: onRename)
            Button(role: .destructive, action: onDelete) {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(meeting.title), \(Self.day.string(from: meeting.startedAt))")
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "< 1 min" }
        return "\(seconds / 60) min"
    }
}

private struct MeetingDetail: View {
    @ObservedObject var model: ScribeAppModel
    let meeting: MeetingRecord

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar
                .padding(.top, 40)
                .padding(.horizontal, 34)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(meeting.title)
                            .font(ScribeTheme.serif(54, weight: .medium))
                            .foregroundStyle(ScribeTheme.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.76)
                        Button {
                            model.showRenameEditor = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(ScribeTheme.faintInk)
                        }
                        .buttonStyle(.plain)
                        .scribePointer()
                        .help("Rename meeting")
                        .disabled(meeting.state == "recording")
                    }
                    HStack(spacing: 9) {
                        Text(Self.date.string(from: meeting.startedAt))
                        Text("•")
                        Text(Self.time.string(from: meeting.startedAt))
                        Text("•")
                        Text(MeetingSidebarRow.duration(meeting.durationSeconds))
                        Text("•")
                        Text(meeting.sourceName)
                    }
                    .font(ScribeTheme.serif(14))
                    .foregroundStyle(ScribeTheme.mutedInk)
                    .padding(.top, 5)

                    ScribeSectionDivider().padding(.vertical, 22)
                    contentSection(title: "Summary") {
                    Text(meeting.summary)
                            .font(ScribeTheme.sans(15))
                            .foregroundStyle(ScribeTheme.ink)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                    }

                    ScribeSectionDivider().padding(.vertical, 22)
                    contentSection(title: "Action Items") {
                        if meeting.actionItems.isEmpty {
                            Text("No action items were identified.")
                                .font(ScribeTheme.sans(13))
                                .foregroundStyle(ScribeTheme.faintInk)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(meeting.actionItems) { item in
                                    Button {
                                        model.toggleAction(item.id)
                                    } label: {
                                        HStack(alignment: .firstTextBaseline, spacing: 11) {
                                            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(item.isComplete ? ScribeTheme.coral : ScribeTheme.faintInk)
                                            Text(item.text)
                                                .font(ScribeTheme.sans(14))
                                                .foregroundStyle(ScribeTheme.ink)
                                                .strikethrough(item.isComplete, color: ScribeTheme.faintInk)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .scribePointer()
                                }
                            }
                        }
                    }

                    if !meeting.userNotes.isEmpty {
                        ScribeSectionDivider().padding(.vertical, 22)
                        contentSection(title: "My Notes") {
                            Text(meeting.userNotes)
                                .font(ScribeTheme.sans(13))
                                .foregroundStyle(ScribeTheme.ink)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                    }

                    ScribeSectionDivider().padding(.vertical, 22)
                    transcriptSection
                    playbackFooter.padding(.top, 22)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.top, 36)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var detailToolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: model.isRecording ? "record.circle.fill" : "checkmark.circle")
                    .foregroundStyle(ScribeTheme.coral)
                Text(model.isRecording ? "Recording · \(model.recordingElapsed)" : statusText)
                    .font(ScribeTheme.sans(12, weight: .medium))
                    .foregroundStyle(ScribeTheme.mutedInk)
                if let transcriptionStatus = model.transcriptionStatus {
                    Text("•")
                        .foregroundStyle(ScribeTheme.faintInk)
                    Text(transcriptionStatus)
                        .font(ScribeTheme.sans(11))
                        .foregroundStyle(ScribeTheme.faintInk)
                }
            }
            Spacer()
            if model.isRecording {
                Button {
                    model.onToggleRecording?()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .buttonStyle(ScribeSecondaryButtonStyle())
            } else {
                Button {
                    model.onToggleRecording?()
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(ScribePrimaryButtonStyle())
            }

            Button {
                model.showNotesEditor = true
            } label: {
                Label("Add note", systemImage: "square.and.pencil")
            }
            .buttonStyle(ScribeSecondaryButtonStyle())

            Button {
                model.copySummary()
            } label: {
                Text("Copy summary")
            }
            .buttonStyle(ScribePrimaryButtonStyle())

            Menu {
                Button("Rename Meeting…", systemImage: "pencil") {
                    model.showRenameEditor = true
                }
                Button(
                    model.regeneratingMeetingID == meeting.id ? "Refreshing notes…" : "Refresh notes",
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    model.regenerateSelectedNote()
                }
                .disabled(meeting.isDemo || !meeting.hasTranscript || meeting.state == "recording" || model.regeneratingMeetingID != nil)
                Button("Export Markdown…", systemImage: "square.and.arrow.down") {
                    model.exportSelectedMeeting()
                }
                Button("Reveal in Finder", systemImage: "folder") {
                    model.revealSelectedMeeting()
                }
                Button("Open transcript", systemImage: "doc.text.magnifyingglass") {
                    model.openTranscript()
                }
                Divider()
                Button(role: .destructive) {
                    model.showDeleteConfirmation = true
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 36)
            .scribePointer()
        }
    }

    private var statusText: String {
        switch meeting.state {
        case "recording": return "Recording in progress"
        case "interrupted": return "Recovered recording"
        default: return meeting.hasTranscript ? "Recording saved" : "Saved · processing locally"
        }
    }

    @ViewBuilder
    private func contentSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(ScribeTheme.serif(23, weight: .semibold))
                .foregroundStyle(ScribeTheme.ink)
            content()
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Transcript")
                    .font(ScribeTheme.serif(23, weight: .semibold))
                    .foregroundStyle(ScribeTheme.ink)
                Spacer()
                if !meeting.transcript.isEmpty {
                    Text("\(meeting.transcript.count) moments")
                        .font(ScribeTheme.sans(10, weight: .medium))
                        .foregroundStyle(ScribeTheme.coral)
                }
            }
            if meeting.transcript.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("The local transcript will appear here when processing finishes.")
                        .font(ScribeTheme.sans(13))
                        .foregroundStyle(ScribeTheme.faintInk)
                }
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(meeting.transcript.prefix(16)) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(line.timestamp)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(ScribeTheme.faintInk)
                                .frame(width: 48, alignment: .leading)
                            Circle()
                                .fill(speakerColor(line.speaker))
                                .frame(width: 5, height: 5)
                            Text(line.speaker)
                                .font(ScribeTheme.sans(10, weight: .semibold))
                                .foregroundStyle(ScribeTheme.mutedInk)
                                .frame(width: 62, alignment: .leading)
                            Text(line.text)
                        .font(ScribeTheme.sans(13))
                                .foregroundStyle(ScribeTheme.ink)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var playbackFooter: some View {
        HStack {
            Button {
                model.togglePlayback()
            } label: {
                Label(
                    model.playingMeetingID == meeting.id ? "Stop playback" : "Play from start",
                    systemImage: model.playingMeetingID == meeting.id ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(ScribeSecondaryButtonStyle())
            .disabled(meeting.isDemo)
            Spacer()
            Button("Open transcript in new window", systemImage: "arrow.up.forward.square") {
                model.openTranscript()
            }
            .buttonStyle(.plain)
            .scribePointer()
            .font(ScribeTheme.sans(11))
            .foregroundStyle(ScribeTheme.mutedInk)
            .disabled(meeting.isDemo)
        }
    }

    private func speakerColor(_ speaker: String) -> Color {
        switch speaker {
        case "YOU", "PRIYA": return ScribeTheme.coral
        case "OTHERS", "JORDAN": return ScribeTheme.blue
        default: return Color.purple.opacity(0.72)
        }
    }

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct EmptyLibrary: View {
    @ObservedObject var model: ScribeAppModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.palette)
                .foregroundStyle(ScribeTheme.coral, ScribeTheme.ink)
            Text(model.searchText.isEmpty ? "Stay in the conversation." : "Nothing found")
                .font(ScribeTheme.serif(34, weight: .medium))
                .foregroundStyle(ScribeTheme.ink)
            Text(model.searchText.isEmpty
                 ? "Start a recording when a conversation matters. Scribe will keep the audio, transcript, and notes together on this Mac."
                 : "Try a different name, topic, person, or phrase.")
                .font(ScribeTheme.sans(14))
                .foregroundStyle(ScribeTheme.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 490)
                .lineSpacing(4)
            if model.searchText.isEmpty {
                Button {
                    model.onToggleRecording?()
                } label: {
                    Label("Start recording", systemImage: "record.circle")
                }
                .buttonStyle(ScribePrimaryButtonStyle())
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MeetingNotesEditor: View {
    @ObservedObject var model: ScribeAppModel
    let meeting: MeetingRecord
    @State private var notes: String

    init(model: ScribeAppModel, meeting: MeetingRecord) {
        self.model = model
        self.meeting = meeting
        _notes = State(initialValue: meeting.userNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("My notes")
                    .font(ScribeTheme.serif(28, weight: .semibold))
                    .foregroundStyle(ScribeTheme.ink)
                Text(meeting.title)
                    .font(ScribeTheme.sans(12))
                    .foregroundStyle(ScribeTheme.mutedInk)
            }
            TextEditor(text: $notes)
                .font(ScribeTheme.sans(14))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.white.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ScribeTheme.divider, lineWidth: 1)
                )
            HStack {
                Text("Saved as plain Markdown beside the recording.")
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.faintInk)
                Spacer()
                Button("Cancel") { model.showNotesEditor = false }
                    .keyboardShortcut(.cancelAction)
                    .scribePointer()
                Button("Save") { model.saveUserNotes(notes) }
                    .buttonStyle(ScribePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 600, height: 420)
        .background(ScribeTheme.paper)
    }
}

struct MeetingRenameEditor: View {
    @ObservedObject var model: ScribeAppModel
    let meeting: MeetingRecord
    @State private var title: String
    @FocusState private var titleIsFocused: Bool

    init(model: ScribeAppModel, meeting: MeetingRecord) {
        self.model = model
        self.meeting = meeting
        _title = State(initialValue: meeting.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Rename meeting")
                    .font(ScribeTheme.serif(28, weight: .semibold))
                    .foregroundStyle(ScribeTheme.ink)
                Text("The folder and note title will stay in sync.")
                    .font(ScribeTheme.sans(12))
                    .foregroundStyle(ScribeTheme.mutedInk)
            }
            TextField("Meeting name", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(ScribeTheme.sans(15))
                .focused($titleIsFocused)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { model.showRenameEditor = false }
                    .keyboardShortcut(.cancelAction)
                    .scribePointer()
                Button("Rename", action: save)
                    .buttonStyle(ScribePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 500, height: 220)
        .background(ScribeTheme.paper)
        .onAppear { titleIsFocused = true }
    }

    private func save() {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        model.renameSelectedMeeting(to: cleaned)
    }
}
