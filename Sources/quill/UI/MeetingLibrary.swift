import AppKit
import AVFoundation
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

struct MeetingActionItem: Identifiable, Hashable, Sendable {
    let id: Int
    let text: String
    var isComplete: Bool
}

struct MeetingTranscriptLine: Identifiable, Hashable, Sendable {
    let id: Int
    let startMilliseconds: Int
    let speaker: String
    let text: String

    var timestamp: String {
        let total = startMilliseconds / 1_000
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}

struct MeetingRecord: Identifiable, Hashable, Sendable {
    let id: String
    let directory: URL
    var title: String
    var startedAt: Date
    var durationSeconds: Int
    var state: String
    var attendees: [String]
    var sourceBundleID: String?
    var summary: String
    var decisions: [String]
    var actionItems: [MeetingActionItem]
    var openQuestions: [String]
    var transcript: [MeetingTranscriptLine]
    var userNotes: String
    var isDemo: Bool = false

    var hasTranscript: Bool { !transcript.isEmpty }

    var sourceName: String {
        guard let sourceBundleID else { return "In person" }
        switch sourceBundleID {
        case "us.zoom.xos": return "Zoom"
        case "com.microsoft.teams2", "com.microsoft.teams": return "Microsoft Teams"
        case "com.tinyspeck.slackmacgap": return "Slack"
        case "com.apple.FaceTime": return "FaceTime"
        case "com.hnc.Discord": return "Discord"
        case "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark": return "Webex"
        case "com.google.Chrome": return "Google Meet · Chrome"
        case "com.apple.Safari": return "Google Meet · Safari"
        case "com.microsoft.edgemac": return "Google Meet · Edge"
        case "org.mozilla.firefox": return "Google Meet · Firefox"
        default: return sourceBundleID
        }
    }

    var searchableText: String {
        ([title, summary, userNotes]
            + attendees
            + decisions
            + actionItems.map(\.text)
            + openQuestions
            + transcript.map { "\($0.speaker) \($0.text)" })
            .joined(separator: " ")
            .lowercased()
    }

    static func demoMeetings(now: Date = Date()) -> [MeetingRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func date(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let transcript = [
            MeetingTranscriptLine(id: 0, startMilliseconds: 5_000, speaker: "PRIYA", text: "Thanks for joining. Let’s start with the beta scope."),
            MeetingTranscriptLine(id: 1, startMilliseconds: 12_000, speaker: "JORDAN", text: "I’ve drafted the scope from our feedback. I’ll walk through it."),
            MeetingTranscriptLine(id: 2, startMilliseconds: 25_000, speaker: "ALEX", text: "Looks solid. We should validate the reporting flow with design."),
            MeetingTranscriptLine(id: 3, startMilliseconds: 31_000, speaker: "PRIYA", text: "Good call. I’ll run a quick review and close those gaps."),
            MeetingTranscriptLine(id: 4, startMilliseconds: 45_000, speaker: "JORDAN", text: "On onboarding, the prototype streamlines setup to three steps."),
            MeetingTranscriptLine(id: 5, startMilliseconds: 62_000, speaker: "ALEX", text: "That’s a big improvement. Let’s test it with a few real users."),
            MeetingTranscriptLine(id: 6, startMilliseconds: 78_000, speaker: "PRIYA", text: "Finally, launch dependencies are docs, analytics, and support coverage."),
            MeetingTranscriptLine(id: 7, startMilliseconds: 91_000, speaker: "ALEX", text: "I’ll confirm owners today and share the status by Friday."),
        ]

        let samples: [(String, Date, Int, String, [MeetingActionItem], [MeetingTranscriptLine], String?)] = [
            (
                "Q4 product planning",
                date(daysAgo: 0, hour: 10, minute: 2),
                42 * 60,
                "The team aligned on September beta milestones, onboarding improvements, and launch readiness. We identified risks for the beta window and agreed on mitigation steps. Two decisions still need owners and will be resolved this week.",
                [
                    MeetingActionItem(id: 0, text: "Priya: Finalize beta scope by Wednesday.", isComplete: false),
                    MeetingActionItem(id: 1, text: "Jordan: Share the onboarding prototype by Thursday.", isComplete: false),
                    MeetingActionItem(id: 2, text: "Alex: Confirm launch dependencies by Friday.", isComplete: false),
                ],
                transcript,
                "us.zoom.xos"
            ),
            ("1:1 with Maya", date(daysAgo: 1, hour: 16, minute: 15), 28 * 60, "Reviewed current priorities, team support, and Maya’s goals for the next month.", [], [], "com.microsoft.teams2"),
            ("Client onboarding — Northstar", date(daysAgo: 2, hour: 11, minute: 8), 36 * 60, "Confirmed kickoff owners, data access, and the first two onboarding milestones.", [], [], "com.google.Chrome"),
            ("Doctor follow-up", date(daysAgo: 3, hour: 9, minute: 30), 12 * 60, "Reviewed test results and the follow-up plan. Schedule the next appointment in six weeks.", [], [], nil),
            ("Kitchen renovation", date(daysAgo: 4, hour: 14), 56 * 60, "Compared cabinet finishes, updated the budget, and confirmed the electrician’s timing.", [], [], "com.apple.FaceTime"),
            ("Parent-teacher check-in", date(daysAgo: 5, hour: 15, minute: 45), 22 * 60, "Discussed progress, reading goals, and two ways to support the next unit at home.", [], [], nil),
        ]

        return samples.map { sample in
            MeetingRecord(
                id: "demo-\(sample.0)",
                directory: URL(fileURLWithPath: "/tmp/scribe-demo/\(sample.0)"),
                title: sample.0,
                startedAt: sample.1,
                durationSeconds: sample.2,
                state: "complete",
                attendees: [],
                sourceBundleID: sample.6,
                summary: sample.3,
                decisions: sample.0 == "Q4 product planning" ? ["Keep the beta focused on the core setup and reporting flows."] : [],
                actionItems: sample.4,
                openQuestions: sample.0 == "Q4 product planning" ? ["Who owns the final support-readiness review?"] : [],
                transcript: sample.5,
                userNotes: sample.0 == "Q4 product planning" ? "Emphasize the simpler setup flow in the launch story." : "",
                isDemo: true
            )
        }
    }
}

enum MeetingLibraryReader {
    private struct Metadata: Decodable {
        let state: String?
        let started: String?
        let duration_seconds: Int?
        let title: String?
        let attendees: [String]?
        let source_bundle_id: String?
    }

    private struct TranscriptFile: Decodable {
        struct Segment: Decodable {
            let speaker: String
            let start_ms: Int
            let text: String
        }
        let segments: [Segment]
    }

    static func readAll(root: URL) -> [MeetingRecord] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories.compactMap(read).sorted { $0.startedAt > $1.startedAt }
    }

    static func read(directory: URL) -> MeetingRecord? {
        let metadataURL = directory.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: data)
        else { return nil }

        let startedAt = metadata.started.flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? fileDate(directory)
            ?? Date.distantPast
        let noteText = (try? String(
            contentsOf: directory.appendingPathComponent("note.md"),
            encoding: .utf8
        )) ?? ""
        let sections = parseSections(noteText)
        let completed = readActionState(directory)
        let actions = parseList(sections["action items"] ?? "")
            .enumerated()
            .map { index, item in
                MeetingActionItem(id: index, text: cleanAction(item), isComplete: completed.contains(index))
            }
        let transcript = readTranscript(directory)
        let userNotes = (try? String(
            contentsOf: directory.appendingPathComponent("user-notes.md"),
            encoding: .utf8
        )) ?? ""

        return MeetingRecord(
            id: directory.path,
            directory: directory,
            title: metadata.title ?? directory.lastPathComponent,
            startedAt: startedAt,
            durationSeconds: metadata.duration_seconds ?? 0,
            state: metadata.state ?? "complete",
            attendees: metadata.attendees ?? [],
            sourceBundleID: metadata.source_bundle_id,
            summary: cleanSection(sections["summary"] ?? fallbackSummary(transcript: transcript)),
            decisions: parseList(sections["decisions"] ?? ""),
            actionItems: actions,
            openQuestions: parseList(sections["open questions"] ?? ""),
            transcript: transcript,
            userNotes: userNotes
        )
    }

    static func saveUserNotes(_ text: String, for meeting: MeetingRecord) throws {
        guard !meeting.isDemo else { return }
        try Data(text.utf8).write(
            to: meeting.directory.appendingPathComponent("user-notes.md"),
            options: .atomic
        )
    }

    static func saveCompletedActions(_ values: Set<Int>, for meeting: MeetingRecord) throws {
        guard !meeting.isDemo else { return }
        let data = try JSONEncoder().encode(values.sorted())
        try data.write(
            to: meeting.directory.appendingPathComponent("action-state.json"),
            options: .atomic
        )
    }

    private static func readTranscript(_ directory: URL) -> [MeetingTranscriptLine] {
        let url = directory.appendingPathComponent("transcript.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TranscriptFile.self, from: data)
        else { return [] }
        return file.segments.enumerated().map { index, segment in
            MeetingTranscriptLine(
                id: index,
                startMilliseconds: segment.start_ms,
                speaker: displaySpeaker(segment.speaker),
                text: segment.text
            )
        }
    }

    private static func readActionState(_ directory: URL) -> Set<Int> {
        let url = directory.appendingPathComponent("action-state.json")
        guard let data = try? Data(contentsOf: url),
              let indexes = try? JSONDecoder().decode([Int].self, from: data)
        else { return [] }
        return Set(indexes)
    }

    private static func parseSections(_ markdown: String) -> [String: String] {
        var result: [String: String] = [:]
        var current: String?
        var lines: [String] = []

        func flush() {
            guard let current else { return }
            result[current] = lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                flush()
                current = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                lines = []
            } else if current != nil && line != "---" {
                lines.append(line)
            }
        }
        flush()
        return result
    }

    private static func parseList(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { return nil }
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func cleanAction(_ text: String) -> String {
        text.replacingOccurrences(of: "[ ] ", with: "")
            .replacingOccurrences(of: "[x] ", with: "")
            .replacingOccurrences(of: "[X] ", with: "")
            .replacingOccurrences(of: "**Owner:** ", with: "")
            .replacingOccurrences(of: "**Due:** ", with: "")
    }

    private static func cleanSection(_ text: String) -> String {
        text.replacingOccurrences(of: "> ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fallbackSummary(transcript: [MeetingTranscriptLine]) -> String {
        transcript.isEmpty
            ? "This meeting is waiting for local transcription."
            : "The transcript is ready. Configure a local summary model in Settings to generate structured notes."
    }

    private static func displaySpeaker(_ raw: String) -> String {
        switch raw.lowercased() {
        case "me": return "YOU"
        case "them": return "OTHERS"
        default: return raw.uppercased()
        }
    }

    private static func fileDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
}

@MainActor
final class ScribeAppModel: ObservableObject {
    struct CaptureSource: Identifiable, Hashable {
        let id: String
        let name: String
        let detail: String
        let symbol: String
        let bundleIDs: Set<String>
    }

    static let captureSources: [CaptureSource] = [
        CaptureSource(id: "zoom", name: "Zoom", detail: "Native Zoom calls", symbol: "video", bundleIDs: ["us.zoom.xos"]),
        CaptureSource(id: "teams", name: "Microsoft Teams", detail: "New and classic Teams", symbol: "person.3", bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"]),
        CaptureSource(id: "browser", name: "Google Meet & browsers", detail: "Chrome, Safari, Edge, and Firefox", symbol: "globe", bundleIDs: ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "org.mozilla.firefox"]),
        CaptureSource(id: "slack", name: "Slack huddles", detail: "Slack desktop audio", symbol: "bubble.left.and.bubble.right", bundleIDs: ["com.tinyspeck.slackmacgap"]),
        CaptureSource(id: "facetime", name: "FaceTime", detail: "Audio and video calls", symbol: "video.circle", bundleIDs: ["com.apple.FaceTime"]),
        CaptureSource(id: "webex", name: "Webex", detail: "Webex Meetings and App", symbol: "person.2.wave.2", bundleIDs: ["com.cisco.webexmeetingsapp", "Cisco-Systems.Spark"]),
        CaptureSource(id: "discord", name: "Discord", detail: "Voice channels and calls", symbol: "headphones", bundleIDs: ["com.hnc.Discord"]),
    ]

    @Published var meetings: [MeetingRecord] = []
    @Published var selectedMeetingID: String?
    @Published var searchText = ""
    @Published var isRecording = false
    @Published var recordingElapsed = "0:00"
    @Published var transcriptionStatus: String?
    @Published var showSettings = false
    @Published var showOnboarding = false
    @Published var showNotesEditor = false
    @Published var alertMessage: String?
    @Published var playingMeetingID: String?
    @Published private(set) var root: URL
    @Published private(set) var promptForCalls: Bool
    @Published private(set) var transcriptionEnabled: Bool
    @Published private(set) var voiceProcessingEnabled: Bool
    @Published private(set) var enabledBundleIDs: Set<String>
    @Published private(set) var launchAtLogin: Bool

    var onToggleRecording: (() -> Void)?
    var onChooseRecordingsFolder: (() -> Void)?
    var onDownloadTranscriptionModel: (() -> Void)?

    private let demo: Bool
    private var playback = MeetingPlaybackController()

    init(root: URL, demo: Bool) {
        self.root = root
        self.demo = demo
        promptForCalls = Config.promptForCalls()
        transcriptionEnabled = Config.transcriptionEnabled()
        voiceProcessingEnabled = Config.micVoiceProcessing()
        enabledBundleIDs = Config.callAppBundleIDs()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        showOnboarding = !demo && !UserDefaults.standard.bool(forKey: "scribe.onboarding.complete")
        refresh()
    }

    var filteredMeetings: [MeetingRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return meetings }
        return meetings.filter { $0.searchableText.contains(query) }
    }

    var selectedMeeting: MeetingRecord? {
        meetings.first { $0.id == selectedMeetingID }
    }

    func refresh(preservingSelection: Bool = true) {
        let previous = preservingSelection ? selectedMeetingID : nil
        meetings = demo ? MeetingRecord.demoMeetings() : MeetingLibraryReader.readAll(root: root)
        if let previous, meetings.contains(where: { $0.id == previous }) {
            selectedMeetingID = previous
        } else {
            selectedMeetingID = meetings.first?.id
        }
    }

    func changeRoot(_ url: URL) {
        root = url
        refresh(preservingSelection: false)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "scribe.onboarding.complete")
        showOnboarding = false
    }

    func copySummary() {
        guard let meeting = selectedMeeting else { return }
        let actions = meeting.actionItems.map { "- \($0.text)" }.joined(separator: "\n")
        let text = """
        # \(meeting.title)

        ## Summary

        \(meeting.summary)

        ## Action items

        \(actions.isEmpty ? "None identified." : actions)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func revealSelectedMeeting() {
        guard let meeting = selectedMeeting, !meeting.isDemo else { return }
        NSWorkspace.shared.activateFileViewerSelecting([meeting.directory])
    }

    func openTranscript() {
        guard let meeting = selectedMeeting, !meeting.isDemo else { return }
        let file = meeting.directory.appendingPathComponent("transcript.md")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        NSWorkspace.shared.open(file)
    }

    func exportSelectedMeeting() {
        guard let meeting = selectedMeeting else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(meeting.title).md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if !meeting.isDemo {
                let source = meeting.directory.appendingPathComponent("note.md")
                if FileManager.default.fileExists(atPath: source.path) {
                    try FileManager.default.copyItem(at: source, to: destination)
                    return
                }
            }
            try Data(renderMarkdown(meeting).utf8).write(to: destination, options: .atomic)
        } catch {
            alertMessage = "Scribe couldn’t export this note: \(error.localizedDescription)"
        }
    }

    func toggleAction(_ id: Int) {
        guard let meetingIndex = meetings.firstIndex(where: { $0.id == selectedMeetingID }),
              let itemIndex = meetings[meetingIndex].actionItems.firstIndex(where: { $0.id == id })
        else { return }
        meetings[meetingIndex].actionItems[itemIndex].isComplete.toggle()
        let meeting = meetings[meetingIndex]
        let completed = Set(meeting.actionItems.filter(\.isComplete).map(\.id))
        do {
            try MeetingLibraryReader.saveCompletedActions(completed, for: meeting)
        } catch {
            alertMessage = "Scribe couldn’t save that action: \(error.localizedDescription)"
        }
    }

    func saveUserNotes(_ text: String) {
        guard let index = meetings.firstIndex(where: { $0.id == selectedMeetingID }) else { return }
        meetings[index].userNotes = text
        do {
            try MeetingLibraryReader.saveUserNotes(text, for: meetings[index])
        } catch {
            alertMessage = "Scribe couldn’t save your notes: \(error.localizedDescription)"
        }
        showNotesEditor = false
    }

    func togglePlayback() {
        guard let meeting = selectedMeeting, !meeting.isDemo else { return }
        if playingMeetingID == meeting.id {
            playback.stop()
            playingMeetingID = nil
            return
        }
        do {
            try playback.play(meeting: meeting)
            playingMeetingID = meeting.id
        } catch {
            playingMeetingID = nil
            alertMessage = "Scribe couldn’t play this recording: \(error.localizedDescription)"
        }
    }

    func setPromptForCalls(_ enabled: Bool) {
        promptForCalls = enabled
        persist { $0.promptForCalls = enabled }
    }

    func setTranscriptionEnabled(_ enabled: Bool) {
        transcriptionEnabled = enabled
        persist {
            var value = $0.transcription ?? .init()
            value.enabled = enabled
            value.engine = value.engine ?? "parakeet"
            $0.transcription = value
        }
    }

    func setVoiceProcessingEnabled(_ enabled: Bool) {
        voiceProcessingEnabled = enabled
        persist { $0.micVoiceProcessing = enabled }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            alertMessage = "Scribe couldn’t update Login Items: \(error.localizedDescription)"
        }
    }

    func isSourceEnabled(_ source: CaptureSource) -> Bool {
        !source.bundleIDs.isDisjoint(with: enabledBundleIDs)
    }

    func setSource(_ source: CaptureSource, enabled: Bool) {
        if enabled {
            enabledBundleIDs.formUnion(source.bundleIDs)
        } else {
            enabledBundleIDs.subtract(source.bundleIDs)
        }
        let values = enabledBundleIDs.sorted()
        persist { $0.callApps = values }
    }

    func modelStatusText() -> String {
        let check = DoctorReport.checkTranscription()
        switch check.status {
        case .ok: return "Ready for local transcription"
        case .warn(let message), .fail(let message): return message
        }
    }

    func openPrivacySettings(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    private func persist(_ change: (inout QuillConfiguration) -> Void) {
        do {
            try Config.update(change)
        } catch {
            alertMessage = "Scribe couldn’t save Settings: \(error.localizedDescription)"
        }
    }

    private func renderMarkdown(_ meeting: MeetingRecord) -> String {
        let actions = meeting.actionItems.map { "- [\($0.isComplete ? "x" : " ")] \($0.text)" }
            .joined(separator: "\n")
        return """
        # \(meeting.title)

        ## Summary

        \(meeting.summary)

        ## Action items

        \(actions.isEmpty ? "_None identified._" : actions)

        ## My notes

        \(meeting.userNotes.isEmpty ? "_No notes._" : meeting.userNotes)
        """
    }
}

private final class MeetingPlaybackController {
    private var players: [AVAudioPlayer] = []

    func play(meeting: MeetingRecord) throws {
        stop()
        let files = ["mic.caf", "system.caf"]
            .map { meeting.directory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }
        players = try files.map { try AVAudioPlayer(contentsOf: $0) }
        players.forEach { $0.prepareToPlay() }
        let start = players.map(\.deviceCurrentTime).max() ?? 0
        players.forEach { $0.play(atTime: start + 0.05) }
    }

    func stop() {
        players.forEach { $0.stop() }
        players.removeAll()
    }
}
