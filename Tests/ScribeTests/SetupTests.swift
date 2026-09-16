import Foundation
import Testing
@testable import Scribe

struct SetupTests {
    @Test("Guided check waits for speech, plays its own chime, and retries only once")
    func automaticChimeSchedule() {
        let ticks = Array(stride(from: AudioSetupGuide.duration, through: 0, by: -1))
        let silent = ticks.filter { AudioSetupGuide.shouldPlayChime(remainingSeconds: $0, systemHasSignal: false) }
        #expect(silent == [7, 4])
        let detected = ticks.filter { AudioSetupGuide.shouldPlayChime(remainingSeconds: $0, systemHasSignal: true) }
        #expect(detected == [7])
        #expect(AudioSetupGuide.instruction(remainingSeconds: 15).hasPrefix("Say:"))
        #expect(AudioSetupGuide.instruction(remainingSeconds: 8).hasPrefix("Say:"))
        #expect(AudioSetupGuide.instruction(remainingSeconds: 7).contains("chime"))
    }

    @Test("A real microphone signal takes precedence over a contradictory permission preflight")
    func microphonePermissionEvidence() {
        #expect(!SetupReadiness.microphoneNeedsReview(reportedDenied: true, verifiedThisLaunch: true))
        #expect(SetupReadiness.microphoneNeedsReview(reportedDenied: true, verifiedThisLaunch: false))
        #expect(!SetupReadiness.microphoneNeedsReview(reportedDenied: false, verifiedThisLaunch: false))
    }

    @Test("Speech after the startup silence window updates microphone health")
    func lateMicrophoneSignal() {
        var check = MicrophoneSignalCheck()
        let initiallySilent = check.observe(frameCount: 96_000, peak: 0, sampleRate: 48_000)
        #expect(initiallySilent)
        #expect(!check.status.hasSignal)
        let lateSpeechNeedsRecovery = check.observe(frameCount: 48_000, peak: 0.2, sampleRate: 48_000)
        #expect(!lateSpeechNeedsRecovery)
        #expect(check.status.hasSignal)
        #expect(check.status.capturedFrames == 144_000)
        #expect(check.status.peak == 0.2)
        // A later quiet interval must neither repeat recovery nor erase the result.
        let quietAgainNeedsRecovery = check.observe(frameCount: 96_000, peak: 0, sampleRate: 48_000)
        #expect(!quietAgainNeedsRecovery)
        #expect(check.status.hasSignal)
    }

    @Test("Microphone health continues measuring after a successful startup check")
    func ongoingMicrophoneSignal() {
        var check = MicrophoneSignalCheck()
        let initiallySilent = check.observe(frameCount: 96_000, peak: 0.001, sampleRate: 48_000)
        let laterSilent = check.observe(frameCount: 48_000, peak: 0.5, sampleRate: 48_000)
        #expect(!initiallySilent)
        #expect(!laterSilent)
        #expect(check.status.capturedFrames == 144_000)
        #expect(check.status.peak == 0.5)
    }

    @Test("Audio setup remembers each track and explains the missing check")
    func persistedTrackResults() throws {
        let suite = "scribe-setup-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let micOnly = AudioSetupVerification(microphone: true, systemAudio: false)
        micOnly.save(to: defaults)
        #expect(AudioSetupVerification.load(from: defaults) == micOnly)
        #expect(!defaults.bool(forKey: "scribe.setup.audioVerified"))
        #expect(micOnly.detail.contains("Mac audio was quiet"))
        let systemOnly = AudioSetupVerification(microphone: false, systemAudio: true)
        #expect(systemOnly.detail.contains("Your microphone was quiet"))
        let both = AudioSetupVerification(microphone: true, systemAudio: true)
        both.save(to: defaults)
        #expect(AudioSetupVerification.load(from: defaults) == both)
        #expect(defaults.bool(forKey: "scribe.setup.audioVerified"))
    }

    @Test("Older audio results preserve success without guessing which track failed")
    func legacyTrackResults() throws {
        let suite = "scribe-setup-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AudioSetupVerification.load(from: defaults) == nil)
        defaults.set(false, forKey: "scribe.setup.audioVerified")
        #expect(AudioSetupVerification.load(from: defaults) == nil)
        defaults.set(true, forKey: "scribe.setup.audioVerified")
        #expect(AudioSetupVerification.load(from: defaults)?.passed == true)
    }

    @Test("Setup never marks missing audio or required transcription as ready")
    func readiness() {
        #expect(!SetupReadiness.canFinish(transcriptionEnabled: true, modelInstalled: true, audioVerified: true, transcriptionVerified: false))
        #expect(!SetupReadiness.canFinish(transcriptionEnabled: true, modelInstalled: false, audioVerified: true, transcriptionVerified: true))
        #expect(!SetupReadiness.canFinish(transcriptionEnabled: true, modelInstalled: true, audioVerified: false, transcriptionVerified: true))
        #expect(!SetupReadiness.canFinish(transcriptionEnabled: false, modelInstalled: false, audioVerified: false, transcriptionVerified: true))
        #expect(SetupReadiness.canFinish(transcriptionEnabled: false, modelInstalled: false, audioVerified: true, transcriptionVerified: true))
        #expect(SetupReadiness.canFinish(transcriptionEnabled: true, modelInstalled: true, audioVerified: true, transcriptionVerified: true))
    }

    @Test("Remembered speaker names seed new meetings without overwriting corrections")
    func profileNames() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try SpeakerIdentity.seedProfile(in: directory, name: "  Charlie \n")
        let path = directory.appendingPathComponent("speaker-names.json")
        #expect(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: path)) == ["me": "Charlie"])
        try SpeakerIdentity.seedProfile(in: directory, name: "Alex")
        #expect(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: path)) == ["me": "Charlie"])
    }

    @Test("Named speakers and per-moment corrections survive transcript export")
    func namedTranscriptExport() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try SpeakerIdentity.seedProfile(in: directory, name: "Charlie")
        try JSONEncoder().encode(["1": "Maya"]).write(to: directory.appendingPathComponent("speaker-overrides.json"))
        try Data(#"{"title":"Weekly check-in","state":"complete"}"#.utf8).write(to: directory.appendingPathComponent("meta.json"))
        let transcript = Transcript(engine: "test", model: "test", created_at: "2026-09-16", segments: [
            .init(speaker: "me", start_ms: 0, end_ms: 1000, text: "Hello"),
            .init(speaker: "them", start_ms: 1000, end_ms: 2000, text: "Hi"),
            .init(speaker: "them", start_ms: 2000, end_ms: 3000, text: "Another voice")
        ])
        try transcript.write(to: directory)
        let markdown = try String(contentsOf: directory.appendingPathComponent("transcript.md"), encoding: .utf8)
        #expect(markdown.contains("Charlie:** Hello"))
        #expect(markdown.contains("Maya:** Hi"))
        #expect(markdown.contains("them:** Another voice"))
        let canonical = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: directory.appendingPathComponent("transcript.json")))
        #expect(canonical.segments.map(\.speaker) == ["me", "them", "them"])
        // Regeneration must keep confirmed names and corrections too.
        try transcript.write(to: directory)
        #expect(try String(contentsOf: directory.appendingPathComponent("transcript.md"), encoding: .utf8) == markdown)
    }

    @Test("Attendee suggestions omit self and blanks, without assigning identities")
    func suggestions() {
        #expect(SpeakerIdentity.suggestions(attendees: [" Charlie ", "Maya", "", "Maya", "Alex"], ownName: "charlie") == ["Alex", "Maya"])
    }

    @Test("Local summary setup rejects missing models and directories")
    func localSummaryFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("llama-cli")
        let model = directory.appendingPathComponent("model.gguf")
        try Data("fixture".utf8).write(to: executable)
        try Data("fixture".utf8).write(to: model)
        #expect(throws: LocalSummarySetup.InvalidFiles.self) {
            try LocalSummarySetup.configuration(executable: executable.path, model: model.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configuration = try LocalSummarySetup.configuration(executable: executable.path, model: model.path)
        #expect(configuration.backend == "llama.cpp")
        #expect(configuration.modelPath == model.path)
        #expect(throws: LocalSummarySetup.InvalidFiles.self) {
            try LocalSummarySetup.configuration(executable: executable.path, model: directory.path)
        }
    }

    @Test("Speaker profile remains compatible with older config files")
    func profileConfiguration() throws {
        #expect(try Config.parse(Data(#"{"speaker_name":"Charlie"}"#.utf8)).speakerName == "Charlie")
        #expect(try Config.parse(Data("{}".utf8)).speakerName == nil)
    }

    @Test("Editing a corrected moment does not relabel every remote speaker")
    func correctionsDoNotBecomeTrackNames() {
        var meeting = MeetingRecord.demoMeetings()[0]
        meeting.speakerNames = [:]
        meeting.transcript = [MeetingTranscriptLine(id: 0, startMilliseconds: 0, speaker: "Maya", text: "Hello", rawSpeaker: "them")]
        meeting.speakerOverrides = [0: "Maya"]
        #expect(SpeakerIdentity.initialNames(for: meeting, profileName: "Charlie") == ["them": "Others"])
    }

    @Test("Finishing a model download never resumes an active recording")
    func doesNotResumeLiveRecording() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("audio".utf8).write(to: directory.appendingPathComponent("mic.caf"))
        try Data(#"{"state":"recording","files":{"mic":"mic.caf"}}"#.utf8)
            .write(to: directory.appendingPathComponent("meta.json"))
        #expect(!TranscriptionCoordinator.shouldResumeSession(directory))
        try Data(#"{"state":"interrupted","files":{"mic":"mic.caf"}}"#.utf8)
            .write(to: directory.appendingPathComponent("meta.json"))
        #expect(TranscriptionCoordinator.shouldResumeSession(directory))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-setup-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
