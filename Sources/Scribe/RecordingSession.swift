import Foundation

struct RecordingCaptureHealth: Equatable, Sendable {
    let microphone: AudioSignalStatus
    let systemAudio: AudioSignalStatus?
    let expectsSystemAudio: Bool

    init(
        microphone: AudioSignalStatus,
        systemAudio: AudioSignalStatus?,
        expectsSystemAudio: Bool = true
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.expectsSystemAudio = expectsSystemAudio
    }

    var missingTracks: [String] {
        var result: [String] = []
        if !microphone.hasSignal { result.append("microphone") }
        if expectsSystemAudio, let systemAudio, !systemAudio.hasSignal {
            result.append("call audio")
        }
        return result
    }

    var hasAnySignal: Bool {
        microphone.hasSignal || systemAudio?.hasSignal == true
    }
}

enum SystemAudioCapturePolicy {
    /// Meeting apps frequently hand audio to helper processes (FaceTime uses
    /// avconferenced; browsers use renderer/audio-service processes). Once a
    /// configured call app is confirmed and the user explicitly chooses
    /// Record, capture the Mac's output mix just as the original Quill did.
    /// Excluding Scribe avoids feeding its own playback back into a meeting.
    static func scope(
        processes: [AudioProcessSnapshot],
        currentPID: pid_t = getpid()
    ) -> SystemAudioRecorder.CaptureScope {
        let ownProcessObjects = processes
            .filter { $0.pid == currentPID }
            .map(\.objectID)
        return .allSystemAudio(excluding: ownProcessObjects)
    }
}

/// One meeting recording: a timestamped folder holding two independent tracks
/// (mic = you, system = them) plus a meta.json written on clean stop. Tracks
/// are separate on purpose — whisper does better on clean single-source audio,
/// and two tracks give free two-party diarization.
final class RecordingSession: @unchecked Sendable {
    let dir: URL
    let startedAt = Date()
    let context: MeetingContext

    private let mic = MicRecorder()
    private let system = SystemAudioRecorder()
    private var sourceBundleID: String?
    private var captureKind = "unknown"
    private var capturesSystemAudio = false

    private var watchdog: Timer?
    private var warnedTracks: Set<String> = []
    private static let watchdogInterval: TimeInterval = 5
    private static let signalWarningDelay: TimeInterval = 12

    /// Create the session folder under `root` (yyyy.MM.dd-HHmm, suffixed on
    /// collision) without starting capture yet.
    init(root: URL, context: MeetingContext) throws {
        self.context = context
        sourceBundleID = context.sourceBundleID
        let base = MeetingFolderNamer.name(startedAt: startedAt, title: context.title)
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            n += 1
        }
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        dir = candidate
        try writeInitialNote()
        try writeMetadata(state: "recording", endedAt: nil)
    }

    /// Start both tracks. If system-output capture fails after the microphone
    /// started, the microphone is torn down so the UI can report the failure
    /// instead of running a misleading half-session.
    func start(allowedBundleIDs: Set<String> = Config.callAppBundleIDs()) throws {
        let processes = try AudioProcessDiscovery.snapshots()
        let runningBundleIDs = AudioProcessDiscovery.runningApplicationBundleIDs()
        let targets = AudioProcessSelector.captureTargets(
            from: processes,
            allowedBundleIDs: allowedBundleIDs,
            runningBundleIDs: runningBundleIDs
        )
        if sourceBundleID == nil {
            let activeBundleIDs = Set(targets.compactMap(\.bundleID))
            if activeBundleIDs.count == 1 { sourceBundleID = activeBundleIDs.first }
        }
        captureKind = sourceBundleID != nil || !targets.isEmpty ? "online" : "unknown"
        // Start the microphone first so macOS can present its consent prompt
        // before a separate system-audio permission interrupts startup.
        try mic.start(writingTo: dir.appendingPathComponent("mic.caf"))
        do {
            try system.start(
                writingTo: dir.appendingPathComponent("system.caf"),
                scope: SystemAudioCapturePolicy.scope(processes: processes)
            )
            capturesSystemAudio = true
        } catch {
            mic.stop()
            capturesSystemAudio = false
            throw error
        }
        try? writeMetadata(state: "recording", endedAt: nil)
        startWatchdog()
    }

    private func startWatchdog() {
        watchdog = Timer.scheduledTimer(
            withTimeInterval: Self.watchdogInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkTrackLiveness()
        }
    }

    /// Stop both tracks, write meta.json, and return whether each expected
    /// track contained a real signal rather than merely valid silent packets.
    @discardableResult
    func stop() -> RecordingCaptureHealth {
        watchdog?.invalidate()
        watchdog = nil
        let microphoneStatus = mic.signalStatus
        let systemStatus = capturesSystemAudio ? system.signalStatus : nil
        if captureKind == "unknown" {
            captureKind = systemStatus?.hasSignal == true ? "online" : "in_person"
        }
        let health = RecordingCaptureHealth(
            microphone: microphoneStatus,
            systemAudio: systemStatus,
            expectsSystemAudio: captureKind == "online"
        )
        mic.stop()
        system.stop()

        let ended = Date()

        // The tracks don't start on the same buffer; record how far each
        // lags the earliest so transcript timestamps share one clock.
        let micStart = mic.firstBufferAt ?? startedAt
        let systemStart = system.firstBufferAt ?? startedAt
        let earliest = min(micStart, systemStart)

        try? writeMetadata(
            state: "complete",
            endedAt: ended,
            startOffsets: [
                "mic": Int(micStart.timeIntervalSince(earliest) * 1000),
                "system": Int(systemStart.timeIntervalSince(earliest) * 1000),
            ],
            captureWarnings: health.missingTracks,
            hasUsableAudio: health.hasAnySignal
        )
        return health
    }

    func captureHealth() -> RecordingCaptureHealth {
        RecordingCaptureHealth(
            microphone: mic.signalStatus,
            systemAudio: capturesSystemAudio ? system.signalStatus : nil,
            expectsSystemAudio: captureKind == "online"
        )
    }

    private func writeMetadata(
        state: String,
        endedAt: Date?,
        startOffsets: [String: Int] = ["mic": 0, "system": 0],
        captureWarnings: [String] = [],
        hasUsableAudio: Bool? = nil
    ) throws {
        let iso = ISO8601DateFormatter()
        var files = ["mic": "mic.caf"]
        if capturesSystemAudio || captureKind == "unknown" { files["system"] = "system.caf" }
        let meta: [String: Any] = [
            "schema_version": 1,
            "state": state,
            "started": iso.string(from: startedAt),
            "ended": endedAt.map(iso.string(from:)) ?? NSNull(),
            "duration_seconds": endedAt.map { Int($0.timeIntervalSince(startedAt)) } ?? 0,
            "title": context.title,
            "attendees": context.attendees,
            "calendar_event_id": context.calendarEventID ?? NSNull(),
            "source_bundle_id": sourceBundleID ?? NSNull(),
            "capture_kind": captureKind,
            "capture_warnings": captureWarnings,
            "has_usable_audio": hasUsableAudio.map { $0 as Any } ?? NSNull(),
            "files": files,
            "start_offset_ms": startOffsets,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: meta,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
    }

    private func writeInitialNote() throws {
        let attendees = context.attendees.isEmpty
            ? "_No calendar attendees available_"
            : context.attendees.map { "- \($0)" }.joined(separator: "\n")
        let note = """
        # \(context.title)

        **Started:** \(ISO8601DateFormatter().string(from: startedAt))

        ## Attendees

        \(attendees)

        ---

        _Recording in progress. Structured notes will be written locally after transcription._
        """
        try Data(note.utf8).write(
            to: dir.appendingPathComponent("note.md"),
            options: .atomic
        )
    }

    private func checkTrackLiveness() {
        guard Date().timeIntervalSince(startedAt) >= Self.signalWarningDelay else { return }
        let health = captureHealth()
        for name in health.missingTracks where warnedTracks.insert(name).inserted {
            notifyUser(
                title: "Scribe: no \(name) detected",
                body: "Scribe is recording, but this track is digitally silent. Check the selected input and call audio before continuing."
            )
        }
    }
}
