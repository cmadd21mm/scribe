import AVFoundation
import CoreAudio
import Testing

@testable import Scribe

struct AudioProcessSelectorTests {
    @Test("Capture targets include only configured processes producing output")
    func filtersUnrelatedAndInactiveProcesses() {
        let processes = [
            snapshot(1, pid: 10, bundleID: "us.zoom.xos", input: true, output: true),
            snapshot(2, pid: 20, bundleID: "com.spotify.client", input: false, output: true),
            snapshot(3, pid: 30, bundleID: "com.microsoft.teams2", input: true, output: false),
            snapshot(4, pid: 40, bundleID: nil, input: true, output: true),
        ]

        let selected = AudioProcessSelector.captureTargets(
            from: processes,
            allowedBundleIDs: ["us.zoom.xos", "com.microsoft.teams2"]
        )

        #expect(selected.map(\.objectID) == [1])
    }

    @Test("Capture target order is stable by PID")
    func stableOrdering() {
        let selected = AudioProcessSelector.captureTargets(
            from: [
                snapshot(8, pid: 50, bundleID: "call", input: true, output: true),
                snapshot(7, pid: 10, bundleID: "call", input: true, output: true),
            ],
            allowedBundleIDs: ["call"]
        )
        #expect(selected.map(\.pid) == [10, 50])
    }

    @Test("Electron and Chromium helper processes map to their configured app")
    func helperBundleIDsAreCanonicalized() {
        let supported = [
            "us.zoom.xos",
            "com.microsoft.teams2",
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "Cisco-Systems.Spark",
            "com.google.Chrome",
            "com.microsoft.edgemac",
        ]
        for bundleID in supported {
            #expect(ConferenceAppMatcher.canonicalBundleID(
                for: bundleID + ".helper.audio",
                allowedBundleIDs: Set(supported)
            ) == bundleID)
        }
    }

    @Test("Safari and FaceTime shared services map to their parent app")
    func appleServiceAliases() {
        let allowed: Set<String> = ["com.apple.Safari", "com.apple.FaceTime"]
        #expect(ConferenceAppMatcher.canonicalBundleID(
            for: "com.apple.WebKit.WebContent",
            allowedBundleIDs: allowed,
            runningBundleIDs: ["com.apple.Safari"],
            allowSharedAliases: true
        ) == "com.apple.Safari")
        #expect(ConferenceAppMatcher.canonicalBundleID(
            for: "com.apple.avconferenced",
            allowedBundleIDs: allowed,
            runningBundleIDs: ["com.apple.FaceTime"],
            allowSharedAliases: true
        ) == "com.apple.FaceTime")
    }

    @Test("Shared Apple helpers require their parent app to be running")
    func sharedHelpersDoNotCreateFalseSources() {
        let allowed: Set<String> = ["com.apple.Safari", "com.apple.FaceTime"]
        #expect(ConferenceAppMatcher.canonicalBundleID(
            for: "com.apple.WebKit.GPU",
            allowedBundleIDs: allowed,
            runningBundleIDs: [],
            allowSharedAliases: true
        ) == nil)
        #expect(ConferenceAppMatcher.canonicalBundleID(
            for: "com.apple.avconferenced",
            allowedBundleIDs: allowed,
            runningBundleIDs: [],
            allowSharedAliases: true
        ) == nil)
    }

    @Test("Shared WebKit output is not used as a manual meeting source")
    func sharedOutputDoesNotMislabelManualCapture() {
        let targets = AudioProcessSelector.captureTargets(
            from: [snapshot(
                12,
                pid: 90,
                bundleID: "com.apple.WebKit.GPU",
                input: false,
                output: true
            )],
            allowedBundleIDs: ["com.apple.Safari"],
            runningBundleIDs: ["com.apple.Safari"]
        )
        #expect(targets.isEmpty)
    }

    @Test("Every advertised app has an exact canonical match")
    func advertisedAppsMatch() {
        for bundleID in Config.defaultCallAppBundleIDs {
            #expect(ConferenceAppMatcher.canonicalBundleID(
                for: bundleID,
                allowedBundleIDs: Config.defaultCallAppBundleIDs
            ) == bundleID)
        }
    }

    @Test("System capture includes helper processes but excludes Scribe itself")
    func globalMeetingCaptureScope() {
        let processes = [
            snapshot(7, pid: 42, bundleID: "com.cmadd21mm.scribe", input: false, output: true),
            snapshot(8, pid: 77, bundleID: "com.apple.FaceTime", input: true, output: true),
            snapshot(9, pid: 88, bundleID: nil, input: false, output: true),
        ]

        let scope = SystemAudioCapturePolicy.scope(processes: processes, currentPID: 42)
        #expect(scope == .allSystemAudio(excluding: [7]))
    }

    @Test("Signal measurement distinguishes digital zero from audible audio")
    func signalMeasurement() throws {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4

        #expect(AudioSignalStatus.peak(in: buffer) == 0)
        buffer.floatChannelData?[1][2] = -0.25
        #expect(AudioSignalStatus.peak(in: buffer) == 0.25)

        #expect(!AudioSignalStatus(capturedFrames: 4, peak: 0).hasSignal)
        #expect(AudioSignalStatus(capturedFrames: 4, peak: 0.25).hasSignal)
    }

    @Test("Capture health accepts either usable track and reports silent tracks")
    func captureHealthPolicy() {
        let health = RecordingCaptureHealth(
            microphone: AudioSignalStatus(capturedFrames: 96_000, peak: 0),
            systemAudio: AudioSignalStatus(capturedFrames: 96_000, peak: 0.2)
        )
        #expect(health.hasAnySignal)
        #expect(health.missingTracks == ["microphone"])
    }

    @Test("In-person capture does not warn about a silent system track")
    func inPersonHealthPolicy() {
        let health = RecordingCaptureHealth(
            microphone: AudioSignalStatus(capturedFrames: 96_000, peak: 0.2),
            systemAudio: AudioSignalStatus(capturedFrames: 96_000, peak: 0),
            expectsSystemAudio: false
        )
        #expect(health.hasAnySignal)
        #expect(health.missingTracks.isEmpty)
    }

    private func snapshot(
        _ objectID: AudioObjectID,
        pid: pid_t,
        bundleID: String?,
        input: Bool,
        output: Bool
    ) -> AudioProcessSnapshot {
        AudioProcessSnapshot(
            objectID: objectID,
            pid: pid,
            bundleID: bundleID,
            isRunningInput: input,
            isRunningOutput: output
        )
    }
}
