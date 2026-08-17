import AppKit
import ArgumentParser
import Foundation

@main
struct Quill: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quill",
        abstract: "Local meeting recorder + transcriber. Records mic and system audio as two tracks, then transcribes on-device.",
        subcommands: [
            Run.self,
            StartRecording.self,
            StopRecording.self,
            OpenRecordings.self,
            QuitDaemon.self,
            ListAudioApps.self,
            TranscribeSession.self,
            RegenerateNote.self,
            RecoverSessions.self,
            Models.self,
            Doctor.self,
            Install.self,
        ],
        defaultSubcommand: Run.self
    )
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the menu-bar daemon (default)."
    )

    @Option(name: .long, help: "Recordings root directory (overrides the config file).")
    var out: String?

    func run() async throws {
        // The async root may dispatch synchronous subcommands on a cooperative
        // executor. Explicitly hop to AppKit's main actor before starting the
        // application run loop.
        try await runMain()
    }

    @MainActor
    private func runMain() throws {
        let root = Config.resolveRoot(cliOverride: out)

        // Non-blocking: permissions prompt on first recording, so warnings at
        // startup are informational, not fatal.
        let checks = DoctorReport.run(recordingsRoot: root)
        if !DoctorReport.allOK(checks) {
            FileHandle.standardError.write(Data("startup checks failed:\n".utf8))
            DoctorReport.print(checks)
            throw ExitCode(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let controller = AppController(root: root)

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            MainActor.assumeIsolated { controller.shutdown() }
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        FileHandle.standardError.write(Data(
            "quill up · recordings → \(root.path) · ^C to quit\n".utf8
        ))
        app.run()
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, system audio, and recordings folder."
    )

    func run() throws {
        let checks = DoctorReport.run(recordingsRoot: Config.resolveRoot(cliOverride: nil))
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

/// Owns the menu bar, the current recording session, and the elapsed-time
/// ticker. All state transitions happen on the main actor.
@MainActor
final class AppController {
    private let root: URL
    private let menuBar = MenuBarController()
    private let transcription = TranscriptionCoordinator()
    private let calendar = CalendarService()
    private var session: RecordingSession?
    private var ticker: Timer?
    private var detectionTicker: Timer?
    private var isStarting = false
    private var controlObservers: [NSObjectProtocol] = []
    private var detector = CallDetectionStateMachine(
        promptAfter: Config.callPromptDelay(),
        endAfter: Config.callEndDelay()
    )

    init(root: URL) {
        self.root = root
        menuBar.onToggle = { [weak self] in self?.toggle() }
        menuBar.onOpenFolder = { [weak self] in self?.openFolder() }
        menuBar.onQuit = { [weak self] in self?.shutdown() }
        menuBar.update(recording: false, elapsed: nil)

        do {
            let recovered = try SessionRecovery.recoverInterrupted(root: root)
            if !recovered.isEmpty {
                FileHandle.standardError.write(Data(
                    "recovered \(recovered.count) interrupted recording(s)\n".utf8
                ))
            }
        } catch {
            FileHandle.standardError.write(Data("recording recovery failed: \(error)\n".utf8))
            notifyUser(
                title: "Quill: recovery failed",
                body: "An interrupted recording could not be recovered: \(error)"
            )
        }

        detectionTicker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.pollForCalls() }
        }
        installControlObservers()

        Task { [transcription, root] in
            await transcription.setStatusHandler { status in
                Task { @MainActor [weak self] in
                    self?.showTranscription(status)
                }
            }
            await transcription.resumePending(root: root)
        }
    }

    /// Stop any live session cleanly (finalizing files) and exit.
    func shutdown() {
        detectionTicker?.invalidate()
        for observer in controlObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        controlObservers.removeAll()
        stopSession()
        NSApp.terminate(nil)
    }

    private func installControlObservers() {
        let center = DistributedNotificationCenter.default()
        controlObservers.append(center.addObserver(
            forName: QuillControlNotification.start,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleIDs = notification.userInfo?["bundle_ids"] as? [String]
            let title = notification.userInfo?["title"] as? String ?? "Manual meeting"
            MainActor.assumeIsolated {
                guard let self, self.session == nil else { return }
                Task {
                    await self.startSession(
                        allowedBundleIDs: bundleIDs.map(Set.init),
                        fallbackTitle: title,
                        sourceBundleID: bundleIDs?.count == 1 ? bundleIDs?.first : nil
                    )
                }
            }
        })
        controlObservers.append(center.addObserver(
            forName: QuillControlNotification.stop,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopSession() }
        })
        controlObservers.append(center.addObserver(
            forName: QuillControlNotification.quit,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        })
    }

    private func toggle() {
        if session == nil {
            Task { await startSession() }
        } else {
            stopSession()
        }
    }

    private func startSession(
        allowedBundleIDs: Set<String>? = nil,
        fallbackTitle: String = "Manual meeting",
        sourceBundleID: String? = nil
    ) async {
        guard !isStarting, session == nil else { return }
        isStarting = true
        defer { isStarting = false }
        let context = await calendar.context(
            at: Date(),
            fallbackTitle: fallbackTitle,
            sourceBundleID: sourceBundleID
        )
        do {
            guard await Permissions.requestMicrophone() else {
                throw RecordingStartError.permission(Permissions.microphoneSettingsMessage)
            }
            try DiskSpaceChecker.requireSpace(
                at: root,
                minimumBytes: Config.minimumFreeDiskBytes()
            )
            let newSession = try RecordingSession(root: root, context: context)
            try newSession.start(allowedBundleIDs: allowedBundleIDs ?? Config.callAppBundleIDs())
            session = newSession
            FileHandle.standardError.write(Data("● recording → \(newSession.dir.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("recording start failed: \(error)\n".utf8))
            let message: String
            if case SystemAudioRecorder.RecorderError.tapCreationFailed = error {
                message = Permissions.systemAudioSettingsMessage
            } else {
                message = "\(error)"
            }
            notifyUser(title: "Quill: recording failed", body: message)
            return
        }

        menuBar.update(recording: true, elapsed: "0:00")
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func pollForCalls() {
        let snapshots: [AudioProcessSnapshot]
        do {
            snapshots = try AudioProcessDiscovery.snapshots()
        } catch {
            FileHandle.standardError.write(Data("call detection failed: \(error)\n".utf8))
            return
        }
        let configured = LiveCallFinder.configuredCalls(
            in: snapshots,
            allowedBundleIDs: Config.callAppBundleIDs()
        )
        for action in detector.update(processes: configured, now: Date()) {
            switch action {
            case .prompt(let call):
                guard session == nil else {
                    detector.decline(bundleID: call.bundleID)
                    continue
                }
                promptToRecord(call)
            case .callEnded:
                if session != nil { stopSession() }
            }
        }
    }

    private func promptToRecord(_ call: LiveCall) {
        let appName = NSRunningApplication.runningApplications(
            withBundleIdentifier: call.bundleID
        ).first?.localizedName ?? call.bundleID
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Record this \(appName) call?"
        alert.informativeText = "Quill never records automatically. Audio stays on this Mac."
        alert.addButton(withTitle: "Record")
        alert.addButton(withTitle: "Not now")
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.startSession(
                    allowedBundleIDs: [call.bundleID],
                    fallbackTitle: "\(appName) call",
                    sourceBundleID: call.bundleID
                )
                if self.session != nil {
                    self.detector.markRecording(bundleID: call.bundleID)
                }
            }
        } else {
            detector.decline(bundleID: call.bundleID)
        }
    }

    private func stopSession() {
        guard let session else { return }
        session.stop()
        let elapsed = Self.format(Date().timeIntervalSince(session.startedAt))
        FileHandle.standardError.write(Data(
            "○ stopped · \(elapsed) · \(session.dir.path)\n".utf8
        ))
        self.session = nil
        ticker?.invalidate()
        ticker = nil
        menuBar.update(recording: false, elapsed: nil)

        let dir = session.dir
        Task { [transcription] in await transcription.enqueue(dir) }
    }

    private func showTranscription(_ status: TranscriptionCoordinator.Status) {
        switch status {
        case .idle:
            menuBar.updateTranscription(nil)
        case .transcribing(let name, let queued):
            menuBar.updateTranscription(
                queued > 0 ? "transcribing \(name) · \(queued) queued" : "transcribing \(name)"
            )
        case .failed(let name):
            menuBar.updateTranscription("transcription failed · \(name)")
        }
    }

    private func tick() {
        guard let session else { return }
        menuBar.update(
            recording: true,
            elapsed: Self.format(Date().timeIntervalSince(session.startedAt))
        )
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

private enum RecordingStartError: Error, CustomStringConvertible {
    case permission(String)

    var description: String {
        switch self {
        case .permission(let message): return message
        }
    }
}
