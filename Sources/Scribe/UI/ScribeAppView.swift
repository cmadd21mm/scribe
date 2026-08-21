import AppKit
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
                    ScribeHome(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ScribeTheme.paper)
        }
        .frame(minWidth: 1_040, minHeight: 700)
        .background(ScribeTheme.paper)
        .preferredColorScheme(model.appearance.colorScheme)
        .sheet(isPresented: $model.showSettings) {
            ScribeSettingsView(model: model)
        }
        .sheet(isPresented: $model.showAISettings) {
            ScribeAISettingsView(model: model)
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
        .sheet(isPresented: $model.showSpeakerEditor) {
            if let meeting = model.selectedMeeting {
                MeetingSpeakerEditor(model: model, meeting: meeting)
            }
        }
        .sheet(isPresented: $model.showAssistant) {
            if let meeting = model.selectedMeeting {
                ScribeAssistantView(model: model, meeting: meeting)
            }
        }
        .sheet(isPresented: $model.showOrganizer) {
            if let meeting = model.selectedMeeting {
                MeetingOrganizerView(model: model, meeting: meeting)
            }
        }
        .sheet(isPresented: $model.showFollowUp) {
            if let meeting = model.selectedMeeting {
                ScribeFollowUpView(meeting: meeting)
            }
        }
        .sheet(isPresented: $model.showDecisionLog) {
            ScribeDecisionLogView(model: model)
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
                set: { if !$0 { model.dismissAlert() } }
            )
        ) {
            if model.alertSettingsPane != nil {
                Button("Open Settings") { model.dismissAlert(openSettings: true) }
                Button("Not now", role: .cancel) { model.dismissAlert() }
            } else {
                Button("OK", role: .cancel) { model.dismissAlert() }
            }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let notice = model.transientNotice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(ScribeTheme.sans(12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(ScribeTheme.button)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: model.transientNotice)
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

                Button {
                    model.showHome()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "house")
                            .font(.system(size: 14, weight: .medium))
                        Text("Home")
                            .font(ScribeTheme.sans(14, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(ScribeTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(model.selectedMeetingID == nil ? ScribeTheme.selection.opacity(0.72) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .scribePointer()
                .accessibilityLabel("Home")
                .accessibilityHint("Shows recording controls and recent meetings")
                .padding(.horizontal, 20)

                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .medium))
                    Text("Meetings")
                        .font(ScribeTheme.sans(12, weight: .semibold))
                    Spacer()
                    Text("\(model.meetings.count)")
                        .font(ScribeTheme.sans(10, weight: .medium))
                        .foregroundStyle(ScribeTheme.faintInk)
                }
                .foregroundStyle(ScribeTheme.mutedInk)
                .padding(.horizontal, 20)

                Button {
                    model.showDecisionLog = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checklist.checked")
                            .font(.system(size: 14, weight: .medium))
                        Text("Decision Log")
                            .font(ScribeTheme.sans(13, weight: .medium))
                        Spacer()
                        Text("\(model.meetings.reduce(0) { $0 + $1.decisions.count })")
                            .font(ScribeTheme.sans(10, weight: .medium))
                            .foregroundStyle(ScribeTheme.faintInk)
                    }
                    .foregroundStyle(ScribeTheme.ink)
                }
                .buttonStyle(.plain)
                .scribePointer()
                .padding(.horizontal, 20)
                .accessibilityLabel("Decision Log, \(model.meetings.reduce(0) { $0 + $1.decisions.count }) decisions")

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ScribeTheme.faintInk)
                    TextField("Search every note", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(ScribeTheme.sans(13))
                        .accessibilityLabel("Search meetings")
                        .accessibilityHint("Searches meeting titles, notes, actions, and transcripts")
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
                .background(ScribeTheme.surface.opacity(0.72))
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
                .accessibilityLabel("Settings")
                .accessibilityHint("Opens recording, transcription, storage, appearance, and permission settings")
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
    @State private var showsFullTranscript = false

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar
                .padding(.top, 40)
                .padding(.horizontal, 34)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(meeting.title)
                            .font(ScribeTheme.serif(48, weight: .medium))
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
                        .accessibilityLabel("Rename meeting")
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

                    if !meeting.workspace.project.isEmpty || !meeting.workspace.people.isEmpty || !meeting.workspace.tags.isEmpty {
                        HStack(spacing: 7) {
                            if !meeting.workspace.project.isEmpty {
                                metadataPill(meeting.workspace.project, symbol: "folder")
                            }
                            ForEach(meeting.workspace.people.prefix(3), id: \.self) { person in
                                metadataPill(person, symbol: "person")
                            }
                            ForEach(meeting.workspace.tags.prefix(2), id: \.self) { tag in
                                metadataPill(tag, symbol: "tag")
                            }
                        }
                        .padding(.top, 10)
                    }

                    ScribeSectionDivider().padding(.vertical, 22)
                    contentSection(title: "Summary") {
                        if meeting.summary.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(model.configuredSummaryAIName.map {
                                    "The transcript is ready. Generate reliable meeting analysis with \($0)."
                                } ?? "The transcript is ready. Connect a separate AI or capable local model to create a reliable summary and action items.")
                                    .font(ScribeTheme.sans(13))
                                    .foregroundStyle(ScribeTheme.mutedInk)
                                if model.regeneratingMeetingID == meeting.id {
                                    summaryProgressCard
                                } else {
                                    if let failure = model.summaryFailure(for: meeting.id) {
                                        Label("The last attempt didn’t finish: \(failure)", systemImage: "exclamationmark.triangle")
                                            .font(ScribeTheme.sans(10))
                                            .foregroundStyle(ScribeTheme.mutedInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Button {
                                        if model.configuredSummaryAIName == nil {
                                            model.showAISettings = true
                                        } else {
                                            model.regenerateSelectedNote()
                                        }
                                    } label: {
                                        Label(
                                            model.summaryFailure(for: meeting.id) == nil
                                                ? model.configuredSummaryAIName.map { "Generate with \($0)" }
                                                    ?? "Set up meeting AI…"
                                                : "Try \(model.configuredSummaryAIName ?? "meeting AI") again",
                                            systemImage: model.configuredSummaryAIName == nil ? "gearshape" : "sparkles"
                                        )
                                    }
                                    .buttonStyle(ScribePrimaryButtonStyle())
                                    .disabled(
                                        meeting.isDemo
                                            || !meeting.hasTranscript
                                            || meeting.state == "recording"
                                            || model.regeneratingMeetingID != nil
                                    )
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(meeting.summary)
                                    .font(ScribeTheme.sans(15))
                                    .foregroundStyle(ScribeTheme.ink)
                                    .lineSpacing(5)
                                    .textSelection(.enabled)
                                if model.regeneratingMeetingID == meeting.id {
                                    summaryProgressCard
                                } else {
                                    Button {
                                        model.regenerateSelectedNote()
                                    } label: {
                                        Label(
                                            model.configuredSummaryAIName.map { "Regenerate with \($0)" }
                                                ?? "Regenerate summary",
                                            systemImage: "arrow.triangle.2.circlepath"
                                        )
                                    }
                                    .buttonStyle(ScribeSecondaryButtonStyle())
                                    .disabled(
                                        meeting.isDemo
                                            || !meeting.hasTranscript
                                            || meeting.state == "recording"
                                            || model.regeneratingMeetingID != nil
                                    )
                                    .accessibilityHint("Replaces the current structured notes after the new result succeeds")
                                }
                            }
                        }
                    }

                    if !meeting.decisions.isEmpty {
                        ScribeSectionDivider().padding(.vertical, 22)
                        contentSection(title: "Decisions") {
                            VStack(alignment: .leading, spacing: 11) {
                                ForEach(Array(meeting.decisions.enumerated()), id: \.offset) { _, decision in
                                    Label {
                                        Text(decision)
                                            .font(ScribeTheme.sans(14))
                                            .foregroundStyle(ScribeTheme.ink)
                                    } icon: {
                                        Image(systemName: "checkmark.seal")
                                            .foregroundStyle(ScribeTheme.coral)
                                    }
                                }
                            }
                        }
                    }

                    ScribeSectionDivider().padding(.vertical, 22)
                    contentSection(title: "Action Items") {
                        if meeting.actionItems.isEmpty {
                            Text(meeting.summary.isEmpty
                                 ? "Action items will appear after a reliable summary is generated."
                                 : "No action items were identified.")
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

                    if !meeting.openQuestions.isEmpty {
                        ScribeSectionDivider().padding(.vertical, 22)
                        contentSection(title: "Open Questions") {
                            VStack(alignment: .leading, spacing: 11) {
                                ForEach(Array(meeting.openQuestions.enumerated()), id: \.offset) { _, question in
                                    Label {
                                        Text(question)
                                            .font(ScribeTheme.sans(14))
                                            .foregroundStyle(ScribeTheme.ink)
                                    } icon: {
                                        Image(systemName: "questionmark.bubble")
                                            .foregroundStyle(ScribeTheme.coral)
                                    }
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
                    model.requestToggleRecording()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .buttonStyle(ScribeSecondaryButtonStyle())
                .accessibilityLabel("Stop recording")
                .accessibilityHint("Stops and saves the current recording")
            } else {
                Button {
                    model.requestToggleRecording()
                } label: {
                    Label(model.isStartingRecording ? "Starting…" : "Record", systemImage: "record.circle")
                }
                .buttonStyle(ScribePrimaryButtonStyle())
                .disabled(model.isStartingRecording)
                .accessibilityLabel(model.isStartingRecording ? "Starting recording" : "Start recording")
                .accessibilityHint("Returns Home and starts a new recording after checking permissions")
            }

            Button {
                model.showNotesEditor = true
            } label: {
                Label("Add note", systemImage: "square.and.pencil")
            }
            .buttonStyle(ScribeSecondaryButtonStyle())
            .accessibilityLabel("Add a personal note")

            Button {
                model.showAssistant = true
            } label: {
                Label("Ask Scribe", systemImage: "sparkles")
            }
            .buttonStyle(ScribeSecondaryButtonStyle())
            .accessibilityLabel("Ask Scribe about this meeting")

            Button {
                model.copySummary()
            } label: {
                Text("Copy summary")
            }
            .buttonStyle(ScribeSecondaryButtonStyle())
            .disabled(meeting.summary.isEmpty)
            .accessibilityHint("Copies the summary, decisions, actions, and open questions")

            Menu {
                Button("Rename Meeting…", systemImage: "pencil") {
                    model.showRenameEditor = true
                }
                Button(
                    model.regeneratingMeetingID == meeting.id
                        ? "Refreshing notes · \(model.summaryGenerationElapsedSeconds)s"
                        : model.configuredSummaryAIName.map { "Refresh with \($0)" }
                            ?? "Refresh notes",
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    model.regenerateSelectedNote()
                }
                .disabled(meeting.isDemo || !meeting.hasTranscript || meeting.state == "recording" || model.regeneratingMeetingID != nil)
                Button("Export Markdown…", systemImage: "square.and.arrow.down") {
                    model.exportSelectedMeeting()
                }
                Button("Organize Meeting…", systemImage: "tag") {
                    model.showOrganizer = true
                }
                Button("Draft Follow-up…", systemImage: "paperplane") {
                    model.showFollowUp = true
                }
                Button("Copy for AI", systemImage: "doc.on.doc") {
                    model.copyAIContext()
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
            .accessibilityLabel("More meeting actions")
        }
    }

    private var statusText: String {
        switch meeting.state {
        case "recording": return "Recording in progress"
        case "interrupted": return "Recovered recording"
        default: return meeting.hasTranscript ? "Recording saved" : "Saved · processing locally"
        }
    }

    private var summaryProgressCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Generating with \(model.configuredSummaryAIName ?? "meeting AI") · \(model.summaryGenerationElapsedSeconds)s")
                    .font(ScribeTheme.sans(12, weight: .semibold))
                    .foregroundStyle(ScribeTheme.ink)
                Text("Scribe keeps the current notes until the new result succeeds. Most requests finish in 10–30 seconds; the request stops after \(ScribeRemoteAIClient.requestTimeoutSeconds) seconds.")
                    .font(ScribeTheme.sans(11))
                    .foregroundStyle(ScribeTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(ScribeTheme.selection.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ScribeTheme.coral.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating meeting summary with \(model.configuredSummaryAIName ?? "meeting AI"), \(model.summaryGenerationElapsedSeconds) seconds elapsed")
    }

    private func metadataPill(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(ScribeTheme.sans(9, weight: .medium))
            .foregroundStyle(ScribeTheme.mutedInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ScribeTheme.selection.opacity(0.55))
            .clipShape(Capsule())
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
                    Button("Name speakers", systemImage: "person.wave.2") {
                        model.showSpeakerEditor = true
                    }
                    .buttonStyle(.plain)
                    .scribePointer()
                    .font(ScribeTheme.sans(10, weight: .medium))
                    .foregroundStyle(ScribeTheme.coral)
                    .accessibilityHint("Opens controls for naming tracks and correcting individual moments")
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
                    ForEach(visibleTranscript) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Button(line.timestamp) {
                                model.playSelectedMeeting(at: line.startMilliseconds)
                            }
                            .buttonStyle(.plain)
                            .scribePointer()
                            .accessibilityLabel("Play transcript from \(line.timestamp)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ScribeTheme.faintInk)
                            .frame(width: 48, alignment: .leading)
                            .help("Play from \(line.timestamp)")
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
                    if meeting.transcript.count > 16 {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                showsFullTranscript.toggle()
                            }
                        } label: {
                            Label(
                                showsFullTranscript
                                    ? "Show less"
                                    : "Show all \(meeting.transcript.count) transcript lines",
                                systemImage: showsFullTranscript ? "chevron.up" : "chevron.down"
                            )
                        }
                        .buttonStyle(ScribeSecondaryButtonStyle())
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private var visibleTranscript: ArraySlice<MeetingTranscriptLine> {
        meeting.transcript.prefix(showsFullTranscript ? meeting.transcript.count : 16)
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
            .accessibilityLabel(model.playingMeetingID == meeting.id ? "Stop meeting playback" : "Play meeting from start")
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

private struct ScribeHome: View {
    @ObservedObject var model: ScribeAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(homeGreeting)
                        .font(ScribeTheme.serif(45, weight: .medium))
                        .foregroundStyle(ScribeTheme.ink)
                    Text("Capture a conversation when it matters. Nothing starts until you choose Record.")
                        .font(ScribeTheme.sans(14))
                        .foregroundStyle(ScribeTheme.mutedInk)
                        .lineSpacing(4)
                }

                recordingCard

                if !model.meetings.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Recent meetings")
                                .font(ScribeTheme.serif(23, weight: .semibold))
                                .foregroundStyle(ScribeTheme.ink)
                            Spacer()
                            Text("Saved locally")
                                .font(ScribeTheme.sans(11, weight: .medium))
                                .foregroundStyle(ScribeTheme.faintInk)
                        }
                        ForEach(model.meetings.prefix(4)) { meeting in
                            Button {
                                model.selectedMeetingID = meeting.id
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: meeting.hasTranscript ? "checkmark.circle" : "waveform")
                                        .font(.system(size: 16))
                                        .foregroundStyle(meeting.hasTranscript ? ScribeTheme.ink : ScribeTheme.coral)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(meeting.title)
                                            .font(ScribeTheme.sans(13, weight: .semibold))
                                            .foregroundStyle(ScribeTheme.ink)
                                            .lineLimit(1)
                                        Text("\(Self.date.string(from: meeting.startedAt)) · \(meeting.sourceName)")
                                            .font(ScribeTheme.sans(11))
                                            .foregroundStyle(ScribeTheme.faintInk)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(ScribeTheme.faintInk)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 58)
                                .background(ScribeTheme.surface.opacity(0.68))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(ScribeTheme.divider, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .scribePointer()
                            .accessibilityLabel("Open \(meeting.title)")
                            .accessibilityHint("Opens this meeting’s summary, actions, and transcript")
                        }
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: model.configuredSummaryAIName == nil ? "sparkles" : "checkmark.seal")
                        .foregroundStyle(ScribeTheme.coral)
                    Text(model.configuredSummaryAIName.map { "Meeting analysis is connected to \($0)." }
                         ?? "Connect meeting AI to generate reliable summaries and action items.")
                        .font(ScribeTheme.sans(11))
                        .foregroundStyle(ScribeTheme.mutedInk)
                    Spacer()
                    Button(model.configuredSummaryAIName == nil ? "Set up" : "AI settings") {
                        model.showAISettings = true
                    }
                    .buttonStyle(.plain)
                    .scribePointer()
                    .font(ScribeTheme.sans(11, weight: .semibold))
                    .foregroundStyle(ScribeTheme.coral)
                    .accessibilityHint("Opens meeting intelligence settings")
                }
                .padding(16)
                .background(ScribeTheme.surface.opacity(0.50))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingCard: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(ScribeTheme.coral.opacity(0.12))
                    .frame(width: 66, height: 66)
                Image(systemName: model.isRecording ? "waveform" : "record.circle.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(ScribeTheme.coral)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(recordingTitle)
                    .font(ScribeTheme.serif(24, weight: .semibold))
                    .foregroundStyle(ScribeTheme.ink)
                Text(recordingDetail)
                    .font(ScribeTheme.sans(12))
                    .foregroundStyle(ScribeTheme.mutedInk)
            }
            Spacer()
            Button {
                model.requestToggleRecording()
            } label: {
                Label(recordingButtonTitle, systemImage: model.isRecording ? "stop.fill" : "record.circle")
                    .frame(minWidth: 112)
            }
            .buttonStyle(ScribePrimaryButtonStyle())
            .disabled(model.isStartingRecording)
            .accessibilityLabel(model.isRecording ? "Stop recording" : model.isStartingRecording ? "Starting recording" : "Start recording")
            .accessibilityHint(model.isRecording ? "Stops and saves the current recording" : "Checks permissions, then records the microphone and supported call audio")
        }
        .padding(24)
        .background(ScribeTheme.surface.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(model.isRecording ? ScribeTheme.coral.opacity(0.55) : ScribeTheme.divider, lineWidth: 1)
        )
    }

    private var recordingTitle: String {
        if model.isRecording { return "Recording · \(model.recordingElapsed)" }
        if model.isStartingRecording { return "Starting recording…" }
        return "Ready to record"
    }

    private var recordingDetail: String {
        if model.isRecording { return "Scribe is saving this conversation locally on your Mac." }
        if model.isStartingRecording { return model.recordingStartDetail }
        return "Works for in-person conversations, Google Meet, Zoom, Teams, and other call apps."
    }

    private var recordingButtonTitle: String {
        if model.isRecording { return "Stop" }
        if model.isStartingRecording { return "Starting…" }
        return "Record"
    }

    private var homeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning." }
        if hour < 18 { return "Good afternoon." }
        return "Good evening."
    }

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
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
                .background(ScribeTheme.surface.opacity(0.72))
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

private struct MeetingSpeakerEditor: View {
    @ObservedObject var model: ScribeAppModel
    let meeting: MeetingRecord
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String]
    @State private var overrides: [Int: String]

    init(model: ScribeAppModel, meeting: MeetingRecord) {
        self.model = model
        self.meeting = meeting
        var initial = meeting.speakerNames
        for line in meeting.transcript where initial[line.rawSpeaker] == nil {
            initial[line.rawSpeaker] = line.speaker == "YOU" ? "Me" : line.speaker.capitalized
        }
        _names = State(initialValue: initial)
        _overrides = State(initialValue: meeting.speakerOverrides)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Name speakers")
                    .font(ScribeTheme.serif(28, weight: .semibold))
                    .foregroundStyle(ScribeTheme.ink)
                Text("Names are saved only with this meeting and update the readable transcript.")
                    .font(ScribeTheme.sans(12))
                    .foregroundStyle(ScribeTheme.mutedInk)
            }

            VStack(spacing: 12) {
                ForEach(speakerIDs, id: \.self) { speakerID in
                    HStack(spacing: 12) {
                        Image(systemName: speakerID == "me" ? "person.crop.circle" : "person.2.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(speakerID == "me" ? ScribeTheme.coral : ScribeTheme.blue)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(speakerID == "me" ? "Microphone track" : "Call audio track")
                                .font(ScribeTheme.sans(10))
                                .foregroundStyle(ScribeTheme.faintInk)
                            TextField("Speaker name", text: binding(for: speakerID))
                                .textFieldStyle(.roundedBorder)
                                .font(ScribeTheme.sans(13))
                        }
                    }
                }
            }

            if speakerIDs.contains("them") && !meeting.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CORRECT INDIVIDUAL MOMENTS")
                        .font(ScribeTheme.sans(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(ScribeTheme.coral)
                    Text("If several people share the call track, type a name beside any moment that needs a correction.")
                        .font(ScribeTheme.sans(10))
                        .foregroundStyle(ScribeTheme.mutedInk)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(meeting.transcript) { line in
                                HStack(alignment: .center, spacing: 9) {
                                    Text(line.timestamp)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(ScribeTheme.faintInk)
                                        .frame(width: 42, alignment: .leading)
                                    Text(line.text)
                                        .font(ScribeTheme.sans(10))
                                        .foregroundStyle(ScribeTheme.mutedInk)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    TextField(names[line.rawSpeaker] ?? line.speaker, text: overrideBinding(for: line.id))
                                        .textFieldStyle(.roundedBorder)
                                        .font(ScribeTheme.sans(10))
                                        .frame(width: 125)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .scribePointer()
                Button("Save names") { model.saveSpeakerDetails(names: names, overrides: overrides) }
                    .buttonStyle(ScribePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 650, height: speakerIDs.contains("them") ? 650 : 380)
        .background(ScribeTheme.paper)
    }

    private var speakerIDs: [String] {
        Array(Set(meeting.transcript.map(\.rawSpeaker))).sorted { lhs, _ in lhs == "me" }
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { names[id] ?? "" },
            set: { names[id] = $0 }
        )
    }

    private func overrideBinding(for id: Int) -> Binding<String> {
        Binding(
            get: { overrides[id] ?? "" },
            set: { overrides[id] = $0 }
        )
    }
}

struct ScribeAssistantView: View {
    enum Scope: String, CaseIterable {
        case meeting = "This meeting"
        case project = "This project"
        case all = "All meetings"
    }

    @ObservedObject var model: ScribeAppModel
    let meeting: MeetingRecord
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var messages: [ScribeChatMessage] = []
    @State private var scope: Scope = .meeting
    @State private var isAnswering = false
    @State private var answerStartedAt: Date?
    @State private var showingAISettings = false
    @FocusState private var questionFocused: Bool

    var body: some View {
        Group {
            if showingAISettings {
                ScribeAISettingsView(model: model) {
                    showingAISettings = false
                    DispatchQueue.main.async {
                        questionFocused = true
                    }
                }
            } else {
                assistantContent
            }
        }
    }

    private var assistantContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask Scribe")
                        .font(ScribeTheme.serif(28, weight: .semibold))
                        .foregroundStyle(ScribeTheme.ink)
                    Text(scope == .meeting
                         ? meeting.title
                         : scope == .project
                            ? "Project: \(meeting.workspace.project)"
                            : "Search across your meeting library")
                        .font(ScribeTheme.sans(12))
                        .foregroundStyle(ScribeTheme.mutedInk)
                }
                Spacer()
                Picker("Scope", selection: $scope) {
                    Text(Scope.meeting.rawValue).tag(Scope.meeting)
                    if !meeting.workspace.project.isEmpty {
                        Text("Project: \(meeting.workspace.project)").tag(Scope.project)
                    }
                    Text(Scope.all.rawValue).tag(Scope.all)
                }
                .labelsHidden()
                .frame(width: 150)
                .scribePointer()
                Button("Done") { dismiss() }
                    .scribePointer()
            }
            .padding(22)

            ScribeSectionDivider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            emptyAssistant
                        }
                        ForEach(messages) { message in
                            chatBubble(message)
                                .id(message.id)
                        }
                        if isAnswering {
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                HStack(spacing: 9) {
                                    ProgressView().controlSize(.small)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Asking \(model.configuredSummaryAIName ?? model.aiSettings.provider.title) · \(answerElapsed(at: timeline.date))s")
                                            .font(ScribeTheme.sans(11, weight: .semibold))
                                            .foregroundStyle(ScribeTheme.mutedInk)
                                        Text("The request stops after 120 seconds; your local notes are never changed.")
                                            .font(ScribeTheme.sans(11))
                                            .foregroundStyle(ScribeTheme.faintInk)
                                    }
                                }
                                .padding(14)
                            }
                        }
                    }
                    .padding(22)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            ScribeSectionDivider()
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Ask about a decision, person, deadline, or topic…", text: $question)
                        .textFieldStyle(.plain)
                        .font(ScribeTheme.sans(13))
                        .foregroundStyle(ScribeTheme.ink)
                        .tint(ScribeTheme.coral)
                        .focused($questionFocused)
                        .onSubmit(ask)
                    Button("Ask", action: ask)
                        .buttonStyle(ScribePrimaryButtonStyle())
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnswering)
                }
                .padding(10)
                .background(ScribeTheme.surface.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ScribeTheme.divider, lineWidth: 1))

                HStack {
                    Label(privacyLabel, systemImage: model.aiSettings.provider == .local ? "lock.shield" : "network")
                        .font(ScribeTheme.sans(9))
                        .foregroundStyle(ScribeTheme.faintInk)
                    Spacer()
                    Button("Copy context") { model.copyAIContext() }
                        .buttonStyle(.plain)
                        .scribePointer()
                        .font(ScribeTheme.sans(10, weight: .medium))
                        .foregroundStyle(ScribeTheme.mutedInk)
                        .accessibilityHint("Copies the selected local meeting context for use elsewhere")
                    Button("AI settings…") {
                        questionFocused = false
                        showingAISettings = true
                    }
                        .buttonStyle(.plain)
                        .scribePointer()
                        .font(ScribeTheme.sans(10, weight: .medium))
                        .foregroundStyle(ScribeTheme.coral)
                        .accessibilityHint("Opens provider, API key, privacy, and model settings")
                }
            }
            .padding(18)
        }
        .frame(width: 760, height: 700)
        .background(ScribeTheme.paper)
        .onAppear { questionFocused = true }
    }

    private var selectedMeetings: [MeetingRecord] {
        switch scope {
        case .meeting: return [meeting]
        case .project:
            return model.meetings.filter { $0.workspace.project == meeting.workspace.project }
        case .all: return model.meetings
        }
    }

    private var privacyLabel: String {
        model.aiSettings.provider == .local
            ? "Runs on this Mac"
            : "Sends selected context to \(model.aiSettings.provider.title) only when you ask"
    }

    private var emptyAssistant: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "sparkles")
                .font(.system(size: 25))
                .foregroundStyle(ScribeTheme.coral)
            Text("Start with something useful")
                .font(ScribeTheme.serif(20, weight: .semibold))
                .foregroundStyle(ScribeTheme.ink)
            VStack(alignment: .leading, spacing: 9) {
                suggestion("What decisions did we make?")
                suggestion("What do I owe, and when?")
                suggestion("Find the moment we discussed launch risk.")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScribeTheme.surface.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            question = text
            questionFocused = true
        } label: {
            HStack(spacing: 10) {
                Text(text)
                    .font(ScribeTheme.sans(12, weight: .medium))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(ScribeTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(ScribeTheme.paper.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ScribeTheme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scribePointer()
        .accessibilityLabel("Use suggested question: \(text)")
    }

    private func chatBubble(_ message: ScribeChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(message.role == .user ? "YOU" : "SCRIBE")
                .font(ScribeTheme.sans(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(message.role == .user ? ScribeTheme.blue : ScribeTheme.coral)
            Text(message.text)
                .font(ScribeTheme.sans(13))
                .foregroundStyle(ScribeTheme.ink)
                .lineSpacing(4)
                .textSelection(.enabled)
            if message.role == .assistant && scope == .meeting {
                let stamps = timestamps(in: message.text)
                if !stamps.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(stamps, id: \.self) { stamp in
                            Button(stamp, systemImage: "play.fill") {
                                model.playSelectedMeeting(at: milliseconds(from: stamp))
                            }
                            .buttonStyle(.plain)
                            .scribePointer()
                            .font(ScribeTheme.sans(9, weight: .medium))
                            .foregroundStyle(ScribeTheme.coral)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? ScribeTheme.selection.opacity(0.60) : ScribeTheme.surface.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func ask() {
        let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isAnswering else { return }
        messages.append(ScribeChatMessage(role: .user, text: value))
        question = ""
        isAnswering = true
        answerStartedAt = Date()
        let settings = model.aiSettings
        let meetings = selectedMeetings
        Task {
            do {
                let answer = try await ScribeMeetingAssistant.answer(
                    question: value,
                    meetings: meetings,
                    settings: settings
                )
                messages.append(ScribeChatMessage(role: .assistant, text: answer))
            } catch {
                messages.append(ScribeChatMessage(
                    role: .assistant,
                    text: "I couldn’t answer that: \(error.localizedDescription)"
                ))
            }
            answerStartedAt = nil
            isAnswering = false
        }
    }

    private func answerElapsed(at date: Date) -> Int {
        guard let answerStartedAt else { return 0 }
        return max(0, Int(date.timeIntervalSince(answerStartedAt)))
    }

    private func timestamps(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}:\d{2}(?::\d{2})?)\]"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Array(Set(regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        })).sorted()
    }

    private func milliseconds(from stamp: String) -> Int {
        let values = stamp.split(separator: ":").compactMap { Int($0) }
        if values.count == 3 { return ((values[0] * 3600) + (values[1] * 60) + values[2]) * 1_000 }
        if values.count == 2 { return ((values[0] * 60) + values[1]) * 1_000 }
        return 0
    }
}

private struct MeetingOrganizerView: View {
    @ObservedObject var model: ScribeAppModel
    let meeting: MeetingRecord
    @Environment(\.dismiss) private var dismiss
    @State private var project: String
    @State private var people: String
    @State private var tags: String

    init(model: ScribeAppModel, meeting: MeetingRecord) {
        self.model = model
        self.meeting = meeting
        _project = State(initialValue: meeting.workspace.project)
        _people = State(initialValue: meeting.workspace.people.joined(separator: ", "))
        _tags = State(initialValue: meeting.workspace.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Organize meeting")
                    .font(ScribeTheme.serif(28, weight: .semibold))
                    .foregroundStyle(ScribeTheme.ink)
                Text("Projects and people make search and cross-meeting questions more useful.")
                    .font(ScribeTheme.sans(12))
                    .foregroundStyle(ScribeTheme.mutedInk)
            }
            organizerField("Project", placeholder: "e.g. Northstar launch", value: $project)
            organizerField("People", placeholder: "Comma-separated names", value: $people)
            organizerField("Tags", placeholder: "e.g. planning, customer, 1:1", value: $tags)
            HStack {
                Label("Saved locally beside this meeting.", systemImage: "internaldrive")
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.faintInk)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .scribePointer()
                Button("Save") {
                    model.saveWorkspace(MeetingWorkspace(
                        project: project.trimmingCharacters(in: .whitespacesAndNewlines),
                        people: split(people),
                        tags: split(tags)
                    ))
                }
                .buttonStyle(ScribePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 590, height: 410)
        .background(ScribeTheme.paper)
    }

    private func organizerField(_ title: String, placeholder: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(ScribeTheme.sans(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(ScribeTheme.coral)
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
                .font(ScribeTheme.sans(13))
        }
    }

    private func split(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ScribeFollowUpView: View {
    let meeting: MeetingRecord
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ScribeFollowUpKind = .recap
    @State private var draft: String

    init(meeting: MeetingRecord) {
        self.meeting = meeting
        _draft = State(initialValue: ScribeFollowUpComposer.draft(kind: .recap, meeting: meeting))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Draft follow-up")
                        .font(ScribeTheme.serif(28, weight: .semibold))
                        .foregroundStyle(ScribeTheme.ink)
                    Text("Nothing is sent automatically.")
                        .font(ScribeTheme.sans(11))
                        .foregroundStyle(ScribeTheme.mutedInk)
                }
                Spacer()
                Picker("Format", selection: $kind) {
                    ForEach(ScribeFollowUpKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                .onChange(of: kind) { _, value in
                    draft = ScribeFollowUpComposer.draft(kind: value, meeting: meeting)
                }
            }
            TextEditor(text: $draft)
                .font(ScribeTheme.sans(13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(ScribeTheme.surface.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ScribeTheme.divider, lineWidth: 1))
            HStack {
                Text("Review and edit before sharing.")
                    .font(ScribeTheme.sans(10))
                    .foregroundStyle(ScribeTheme.faintInk)
                Spacer()
                Button("Done") { dismiss() }
                    .scribePointer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft, forType: .string)
                }
                .buttonStyle(ScribePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 720, height: 620)
        .background(ScribeTheme.paper)
    }
}

private struct ScribeDecisionLogView: View {
    @ObservedObject var model: ScribeAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Decision log")
                        .font(ScribeTheme.serif(28, weight: .semibold))
                        .foregroundStyle(ScribeTheme.ink)
                    Text("Every captured decision, linked back to its meeting.")
                        .font(ScribeTheme.sans(12))
                        .foregroundStyle(ScribeTheme.mutedInk)
                }
                Spacer()
                Button("Done") { dismiss() }.scribePointer()
            }
            .padding(24)
            ScribeSectionDivider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if decisions.isEmpty {
                        ContentUnavailableView(
                            "No decisions yet",
                            systemImage: "checklist.checked",
                            description: Text("Decisions identified in meeting notes will collect here.")
                        )
                        .foregroundStyle(ScribeTheme.mutedInk)
                        .frame(maxWidth: .infinity, minHeight: 340)
                    } else {
                        ForEach(decisions, id: \.id) { entry in
                            Button {
                                model.selectedMeetingID = entry.meeting.id
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(ScribeTheme.coral)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.text)
                                            .font(ScribeTheme.sans(13, weight: .medium))
                                            .foregroundStyle(ScribeTheme.ink)
                                            .multilineTextAlignment(.leading)
                                        Text("\(entry.meeting.title) · \(Self.date.string(from: entry.meeting.startedAt))")
                                            .font(ScribeTheme.sans(10))
                                            .foregroundStyle(ScribeTheme.faintInk)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(ScribeTheme.faintInk)
                                }
                                .padding(14)
                                .background(ScribeTheme.surface.opacity(0.68))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .scribePointer()
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 700, height: 620)
        .background(ScribeTheme.paper)
    }

    private struct Entry: Identifiable {
        let id: String
        let text: String
        let meeting: MeetingRecord
    }

    private var decisions: [Entry] {
        model.meetings.flatMap { meeting in
            meeting.decisions.enumerated().map { index, value in
                Entry(id: "\(meeting.id)-\(index)", text: value, meeting: meeting)
            }
        }
    }

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
