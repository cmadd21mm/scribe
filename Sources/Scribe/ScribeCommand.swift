import AppKit
import ArgumentParser
import Foundation
import SwiftUI

@main
struct ScribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scribe",
        abstract: "Private, local-first meeting notes for macOS.",
        subcommands: [
            Run.self,
            StartRecording.self,
            StopRecording.self,
            OpenRecordings.self,
            QuitDaemon.self,
            ListAudioApps.self,
            TranscribeSession.self,
            RegenerateNote.self,
            ConfigureAI.self,
            SetMeetingSource.self,
            RecoverSessions.self,
            Models.self,
            Doctor.self,
            Install.self,
            DemoSnapshot.self,
        ],
        defaultSubcommand: Run.self
    )
}

private enum DemoSnapshotScreen: String, ExpressibleByArgument {
    case library
    case meeting
    case summary
    case assistant
    case rename
    case settings
    case models
    case intelligence
    case onboarding
}

struct DemoSnapshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Render the built-in demo library to a PNG for visual regression review."
    )

    @Option(name: .long, help: "PNG output path.")
    var output: String = "scribe-demo.png"

    @Option(name: .long, help: "Screen to render: library, meeting, summary, assistant, rename, settings, models, intelligence, or onboarding.")
    private var screen: DemoSnapshotScreen = .library

    @Option(name: .long, help: "Appearance to render: light or dark.")
    private var appearance: String = "light"

    func run() async throws {
        try await render()
    }

    @MainActor
    private func render() throws {
        let model = ScribeAppModel(root: URL(fileURLWithPath: "/tmp/scribe-demo"), demo: true)
        let size: CGSize
        let selectedView: AnyView
        switch screen {
        case .library:
            size = CGSize(width: 1_440, height: 1_024)
            selectedView = AnyView(ScribeAppView(model: model))
        case .meeting:
            size = CGSize(width: 1_440, height: 1_024)
            model.selectedMeetingID = model.meetings[0].id
            selectedView = AnyView(ScribeAppView(model: model))
        case .summary:
            size = CGSize(width: 1_440, height: 1_024)
            model.selectedMeetingID = model.meetings[0].id
            model.regeneratingMeetingID = model.meetings[0].id
            model.summaryGenerationElapsedSeconds = 18
            selectedView = AnyView(ScribeAppView(model: model))
        case .assistant:
            size = CGSize(width: 760, height: 700)
            selectedView = AnyView(ScribeAssistantView(model: model, meeting: model.meetings[0]))
        case .rename:
            size = CGSize(width: 500, height: 220)
            selectedView = AnyView(MeetingRenameEditor(model: model, meeting: model.meetings[0]))
        case .settings:
            size = CGSize(width: 680, height: 760)
            selectedView = AnyView(ScribeSettingsView(model: model))
        case .models:
            size = CGSize(width: 610, height: 490)
            selectedView = AnyView(ScribeModelManagerView(model: model))
        case .intelligence:
            size = CGSize(width: 640, height: 690)
            selectedView = AnyView(ScribeAISettingsView(model: model, apiKeyOverride: ""))
        case .onboarding:
            size = CGSize(width: 760, height: 570)
            selectedView = AnyView(ScribeOnboardingView(model: model))
        }
        let scheme: ColorScheme
        switch appearance.lowercased() {
        case "light": scheme = .light
        case "dark": scheme = .dark
        default: throw ValidationError("appearance must be light or dark")
        }
        let content = selectedView
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw ValidationError("could not render the demo window")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ValidationError("could not encode the demo window")
        }
        let url = URL(fileURLWithPath: Config.expandPath(output))
        try png.write(to: url, options: .atomic)
        print(url.path)
    }
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the menu-bar daemon (default)."
    )

    @Option(name: .long, help: "Recordings root directory (overrides the config file).")
    var out: String?

    @Flag(name: .long, help: "Open the app with built-in sample meetings for screenshots and design review.")
    var demo = false

    func run() async throws {
        // The async root may dispatch synchronous subcommands on a cooperative
        // executor. Explicitly hop to AppKit's main actor before starting the
        // application run loop.
        try await runMain()
    }

    @MainActor
    private func runMain() throws {
        let root = Config.resolveRoot(cliOverride: out)

        // Permissions are intentionally non-blocking. Scribe should always
        // open, explain what is missing, and ask only when the user records.
        let checks = DoctorReport.run(recordingsRoot: root)
        if !DoctorReport.allOK(checks) {
            FileHandle.standardError.write(Data("startup checks need attention:\n".utf8))
            DoctorReport.print(checks)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let controller = AppController(root: root, demo: demo)

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            MainActor.assumeIsolated { controller.shutdown() }
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        FileHandle.standardError.write(Data(
            "Scribe is open · recordings → \(root.path) · ^C to quit\n".utf8
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
    private var root: URL
    private let demo: Bool
    private let menuBar: MenuBarController
    private let model: ScribeAppModel
    private let windowController: ScribeWindowController
    private let mainMenu: ScribeMainMenu
    private let updater: ScribeUpdater
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

    init(root: URL, demo: Bool = false) {
        self.root = root
        self.demo = demo
        menuBar = MenuBarController()
        model = ScribeAppModel(root: root, demo: demo)
        windowController = ScribeWindowController(model: model, demo: demo)
        mainMenu = ScribeMainMenu()
        updater = ScribeUpdater()

        menuBar.onToggle = { [weak self] in self?.toggle() }
        menuBar.onOpenApp = { [weak self] in self?.windowController.present() }
        menuBar.onOpenFolder = { [weak self] in self?.openFolder() }
        menuBar.onSettings = { [weak self] in self?.openSettings() }
        menuBar.onCheckForUpdates = { [weak self] in self?.updater.checkForUpdates() }
        menuBar.onQuit = { [weak self] in self?.shutdown() }
        menuBar.update(recording: false, elapsed: nil)

        mainMenu.onToggleRecording = { [weak self] in self?.toggle() }
        mainMenu.onOpenFolder = { [weak self] in self?.openFolder() }
        mainMenu.onOpenSettings = { [weak self] in self?.openSettings() }
        mainMenu.onCheckForUpdates = { [weak self] in self?.updater.checkForUpdates() }
        mainMenu.onQuit = { [weak self] in self?.shutdown() }
        mainMenu.install()

        model.onToggleRecording = { [weak self] in self?.toggle() }
        model.onChooseRecordingsFolder = { [weak self] in self?.chooseRecordingsFolder() }
        model.onCheckForUpdates = { [weak self] in self?.updater.checkForUpdates() }
        model.onDownloadTranscriptionModel = { [weak self] selected in
            self?.downloadTranscriptionModel(selected)
        }
        windowController.present()

        guard !demo else { return }

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
                title: "Scribe: recovery failed",
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
            forName: ScribeControlNotification.start,
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
            forName: ScribeControlNotification.stop,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopSession() }
        })
        controlObservers.append(center.addObserver(
            forName: ScribeControlNotification.quit,
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
        guard !isStarting, session == nil else {
            model.isStartingRecording = false
            return
        }
        isStarting = true
        model.isStartingRecording = true
        model.showHome()
        windowController.present()
        defer {
            isStarting = false
            model.isStartingRecording = false
        }
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
            let presentation = RecordingFailureMapper.presentation(for: error)
            model.alertMessage = presentation.message
            model.alertSettingsPane = presentation.settingsPane
            windowController.present()
            notifyUser(title: "Scribe: recording failed", body: presentation.message)
            return
        }

        menuBar.update(recording: true, elapsed: "0:00")
        model.isRecording = true
        model.recordingElapsed = "0:00"
        model.refresh()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func pollForCalls() {
        guard Config.promptForCalls() else { return }
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
        alert.informativeText = "Scribe never records automatically. Audio stays on this Mac."
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
        model.isRecording = false
        model.recordingElapsed = "0:00"
        model.refresh()

        let dir = session.dir
        Task { [transcription] in await transcription.enqueue(dir) }
    }

    private func showTranscription(_ status: TranscriptionCoordinator.Status) {
        switch status {
        case .idle:
            menuBar.updateTranscription(nil)
            model.transcriptionStatus = nil
            model.refresh()
        case .transcribing(_, let queued):
            let text = queued > 0 ? "Transcribing · \(queued) queued" : "Transcribing locally"
            menuBar.updateTranscription(text.lowercased())
            model.transcriptionStatus = text
        case .failed(let name):
            menuBar.updateTranscription("transcription failed · \(name)")
            model.transcriptionStatus = "Transcription needs attention"
            model.refresh()
        }
    }

    private func tick() {
        guard let session else { return }
        let elapsed = Self.format(Date().timeIntervalSince(session.startedAt))
        menuBar.update(recording: true, elapsed: elapsed)
        model.recordingElapsed = elapsed
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    private func openSettings() {
        windowController.present()
        model.showSettings = true
    }

    private func chooseRecordingsFolder() {
        guard session == nil else {
            model.alertMessage = "Stop the current recording before changing its folder."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose where Scribe keeps recordings"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        do {
            try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
            try Config.update { $0.recordingsDir = selected.path }
            root = selected
            model.changeRoot(selected)
        } catch {
            model.alertMessage = "Scribe couldn’t use that folder: \(error.localizedDescription)"
        }
    }

    private func downloadTranscriptionModel(_ selected: LocalTranscriptionModel) {
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "scribe")
        Task { [weak self] in
            let result = await Self.runModelDownload(executable: executable, model: selected)
            guard let self else { return }
            if result.status == 0 {
                model.finishModelDownload(selected)
            } else {
                model.finishModelDownload(selected, error: result.output)
            }
        }
    }

    private struct ModelDownloadResult: Sendable {
        let status: Int32
        let output: String
    }

    nonisolated private static func runModelDownload(
        executable: URL,
        model: LocalTranscriptionModel
    ) async -> ModelDownloadResult {
        await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["models", "download-transcription", "--model", model.rawValue]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(
                    data: pipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                return ModelDownloadResult(status: process.terminationStatus, output: output)
            } catch {
                return ModelDownloadResult(status: -1, output: error.localizedDescription)
            }
        }.value
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

enum RecordingStartError: Error, CustomStringConvertible {
    case permission(String)

    var description: String {
        switch self {
        case .permission(let message): return message
        }
    }
}

struct RecordingFailurePresentation: Equatable {
    let message: String
    let settingsPane: String?
}

enum RecordingFailureMapper {
    static func presentation(for error: Error) -> RecordingFailurePresentation {
        switch error {
        case RecordingStartError.permission(let message):
            return RecordingFailurePresentation(
                message: message,
                settingsPane: "Privacy_Microphone"
            )
        case SystemAudioRecorder.RecorderError.tapCreationFailed:
            return RecordingFailurePresentation(
                message: Permissions.systemAudioSettingsMessage,
                settingsPane: "Privacy_ScreenCapture"
            )
        default:
            return RecordingFailurePresentation(
                message: "Scribe couldn’t start recording: \(error)",
                settingsPane: nil
            )
        }
    }
}
