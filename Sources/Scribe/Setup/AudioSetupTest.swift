import AppKit
import AVFoundation
import Combine

/// Uses the production capture path, but keeps test audio out of the library.
/// A test starts only after an explicit click and always stops after 15 seconds.
@MainActor
final class AudioSetupTest: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var microphoneHasSignal = false
    @Published private(set) var systemHasSignal = false
    @Published private(set) var remainingSeconds = AudioSetupGuide.duration
    @Published private(set) var transcript = ""
    @Published private(set) var message: String?
    @Published private(set) var testSoundError: String?
    @Published private(set) var verification = AudioSetupVerification.load(from: .standard)
    @Published private(set) var microphoneVerifiedThisLaunch = false
    @Published private(set) var hasRecording = false
    @Published private(set) var verifiedTranscriptionModelID = UserDefaults.standard.string(forKey: "scribe.setup.transcriptionVerified")
    var canStart: (() -> Bool)?
    private var session: RecordingSession?
    private var testRoot: URL?
    private var directory: URL?
    private var timer: Timer?
    private var players: [AVAudioPlayer] = []
    private var testSound: Process?
    private var generation = UUID()
    var isBusy: Bool { isRecording || isTranscribing }
    var verified: Bool { verification?.passed == true }
    var microphoneAccessNeedsReview: Bool {
        // AVAudioEngine can capture successfully even when the AVCaptureDevice
        // preflight reports denied. Prefer a real signal observed this launch;
        // check permissions again after relaunch or when a new test fails.
        SetupReadiness.microphoneNeedsReview(reportedDenied: Permissions.microphoneIsDenied,
                                            verifiedThisLaunch: microphoneVerifiedThisLaunch)
    }
    var verificationDetail: String {
        verification?.detail ?? "The audio check has not passed yet. Run it again to check your microphone and Mac audio separately."
    }

    init() {
        microphoneHasSignal = verification?.microphone == true
        systemHasSignal = verification?.systemAudio == true
    }

    func start() {
        guard !isBusy else { return }
        guard canStart?() == true else {
            message = "Stop the meeting recording before starting an audio test."
            return
        }
        discard()
        verification = nil
        microphoneVerifiedThisLaunch = false
        UserDefaults.standard.removeObject(forKey: "scribe.setup.audioTracks")
        verifiedTranscriptionModelID = nil
        UserDefaults.standard.removeObject(forKey: "scribe.setup.transcriptionVerified")
        UserDefaults.standard.set(false, forKey: "scribe.setup.audioVerified")
        microphoneHasSignal = false
        systemHasSignal = false
        transcript = ""
        message = nil
        testSoundError = nil
        remainingSeconds = AudioSetupGuide.duration
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-audio-test-\(UUID().uuidString)")
            testRoot = root
            try DiskSpaceChecker.requireSpace(at: root, minimumBytes: Config.minimumFreeDiskBytes())
            let capture = try RecordingSession(root: root, context: .fallback(title: "Audio setup test", sourceBundleID: nil))
            try capture.start()
            session = capture
            directory = capture.dir
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let session = self.session else { return }
                    let health = session.captureHealth()
                    self.microphoneHasSignal = health.microphone.hasSignal
                    self.systemHasSignal = health.systemAudio?.hasSignal == true
                    self.remainingSeconds -= 1
                    if AudioSetupGuide.shouldPlayChime(remainingSeconds: self.remainingSeconds, systemHasSignal: self.systemHasSignal) {
                        self.playTestSound()
                    }
                    if self.remainingSeconds <= 0 { self.stop() }
                }
            }
        } catch {
            message = Permissions.microphoneIsDenied
                ? Permissions.microphoneSettingsMessage
                : RecordingFailureMapper.presentation(for: error).message
            discard()
        }
    }

    private func playTestSound() {
        guard isRecording else { return }
        guard testSound?.isRunning != true else { return }
        // The production tap excludes Scribe's own audio. A system player
        // exercises the external-app path that real calls use.
        let sound = Process()
        sound.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        sound.arguments = ["/System/Library/Sounds/Glass.aiff"]
        let token = generation
        sound.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                guard let self, self.generation == token, self.isRecording else { return }
                if status != 0 {
                    self.testSoundError = "The test chime couldn’t play. Check your Mac’s sound output, then try the check again."
                }
            }
        }
        do {
            try sound.run()
            testSound = sound
            testSoundError = nil
        } catch {
            testSoundError = "The test chime couldn’t start. Try the check again."
        }
    }

    func stop() {
        guard let session else { return }
        timer?.invalidate()
        timer = nil
        let health = session.stop()
        self.session = nil
        isRecording = false
        if let testSound, testSound.isRunning { testSound.terminate() }
        testSound = nil
        hasRecording = true
        microphoneHasSignal = health.microphone.hasSignal
        systemHasSignal = health.systemAudio?.hasSignal == true
        microphoneVerifiedThisLaunch = microphoneHasSignal
        let result = AudioSetupVerification(microphone: microphoneHasSignal, systemAudio: systemHasSignal)
        verification = result
        result.save(to: .standard)
        message = verified
            ? "Both audio tracks received sound. Play them back to check clarity."
            : result.detail
        if LocalTranscriptionModel.selected.isInstalled { transcribe() }
    }

    func transcribe() {
        guard !isBusy, let directory, hasRecording else { return }
        let token = generation
        isTranscribing = true
        Task {
            do {
                let selectedModel = LocalTranscriptionModel.selected
                let engine = ParakeetEngine(model: selectedModel)
                try await engine.prepare()
                let lines: [TranscriptSegment]
                do {
                    lines = try await engine.transcribe(directory.appendingPathComponent("mic.caf"))
                    await engine.release()
                } catch {
                    await engine.release()
                    throw error
                }
                guard token == generation else { return }
                transcript = lines.map(\.text).joined(separator: " ")
                if transcript.isEmpty { message = "No words were recognized. Try again and say a complete sentence." }
                else {
                    verifiedTranscriptionModelID = selectedModel.id
                    UserDefaults.standard.set(selectedModel.id, forKey: "scribe.setup.transcriptionVerified")
                }
            } catch {
                guard token == generation else { return }
                message = "Test transcription failed: \(error). Retry after checking the transcription model."
            }
            guard token == generation else { return }
            isTranscribing = false
        }
    }

    func play(track: String) {
        guard hasRecording, let directory, ["mic", "system"].contains(track) else { return }
        players.forEach { $0.stop() }
        do {
            let player = try AVAudioPlayer(contentsOf: directory.appendingPathComponent("\(track).caf"))
            players = [player]
            player.play()
        } catch { message = "Couldn’t play the test audio: \(error.localizedDescription)" }
    }

    func discard() {
        generation = UUID()
        timer?.invalidate()
        timer = nil
        if let session { _ = session.stop() }
        session = nil
        players.forEach { $0.stop() }
        players = []
        if let testSound, testSound.isRunning { testSound.terminate() }
        testSound = nil
        isRecording = false
        isTranscribing = false
        hasRecording = false
        if let testRoot { try? FileManager.default.removeItem(at: testRoot) }
        testRoot = nil
        directory = nil
    }
}
