import CoreAudio
import Foundation
import Testing

@testable import Scribe

struct CallDetectionStateMachineTests {
    @Test("A live call prompts only after the configured delay")
    func delayedPrompt() {
        var machine = CallDetectionStateMachine(promptAfter: 5, endAfter: 10)
        let start = Date(timeIntervalSince1970: 100)
        let call = [process(input: true, output: true)]

        #expect(machine.update(processes: call, now: start).isEmpty)
        #expect(machine.update(processes: call, now: start.addingTimeInterval(4)).isEmpty)
        #expect(machine.update(processes: call, now: start.addingTimeInterval(5)) == [
            .prompt(LiveCall(bundleID: "us.zoom.xos", processObjectIDs: [7]))
        ])
    }

    @Test("Output-only media never prompts")
    func requiresInputAndOutput() {
        var machine = CallDetectionStateMachine(promptAfter: 0, endAfter: 10)
        let now = Date(timeIntervalSince1970: 100)
        #expect(machine.update(
            processes: [process(input: false, output: true)],
            now: now
        ).isEmpty)
        #expect(machine.update(
            processes: [process(input: false, output: true)],
            now: now.addingTimeInterval(20)
        ).isEmpty)
    }

    @Test("Microphone use prompts even when call output belongs to a helper")
    func inputIsSufficientForPrompt() {
        var machine = CallDetectionStateMachine(promptAfter: 0, endAfter: 10)
        let now = Date(timeIntervalSince1970: 100)
        let inputOnly = [process(input: true, output: false)]
        #expect(machine.update(processes: inputOnly, now: now).isEmpty)
        #expect(machine.update(processes: inputOnly, now: now) == [
            .prompt(LiveCall(bundleID: "us.zoom.xos", processObjectIDs: [7]))
        ])
    }

    @Test("Browser input and output helpers combine into one canonical call")
    func splitBrowserHelpers() {
        let raw = [
            process(
                id: 7,
                bundleID: "com.google.Chrome.helper.audio",
                input: true,
                output: false
            ),
            process(
                id: 8,
                bundleID: "com.google.Chrome.helper.renderer",
                input: false,
                output: true
            ),
        ]
        let configured = LiveCallFinder.configuredCalls(
            in: raw,
            allowedBundleIDs: ["com.google.Chrome"]
        )
        #expect(configured.map(\.bundleID) == ["com.google.Chrome", "com.google.Chrome"])

        var machine = CallDetectionStateMachine(promptAfter: 0, endAfter: 10)
        let now = Date(timeIntervalSince1970: 100)
        #expect(machine.update(processes: configured, now: now).isEmpty)
        #expect(machine.update(processes: configured, now: now) == [
            .prompt(LiveCall(bundleID: "com.google.Chrome", processObjectIDs: [7, 8]))
        ])
    }

    @Test("Declining suppresses prompts until the call ends")
    func declinedCallDoesNotReprompt() {
        var machine = CallDetectionStateMachine(promptAfter: 1, endAfter: 10)
        let start = Date(timeIntervalSince1970: 100)
        let call = [process(input: true, output: true)]
        _ = machine.update(processes: call, now: start)
        _ = machine.update(processes: call, now: start.addingTimeInterval(1))
        machine.decline(bundleID: "us.zoom.xos")
        #expect(machine.update(
            processes: call,
            now: start.addingTimeInterval(100)
        ).isEmpty)

        _ = machine.update(processes: [], now: start.addingTimeInterval(101))
        #expect(machine.update(processes: call, now: start.addingTimeInterval(102)).isEmpty)
        #expect(machine.update(processes: call, now: start.addingTimeInterval(103)) == [
            .prompt(LiveCall(bundleID: "us.zoom.xos", processObjectIDs: [7]))
        ])
    }

    @Test("An explicitly accepted recording ends after the stop grace period")
    func recordingEndsAfterGracePeriod() {
        var machine = CallDetectionStateMachine(promptAfter: 1, endAfter: 5)
        let start = Date(timeIntervalSince1970: 100)
        let call = [process(input: true, output: true)]
        _ = machine.update(processes: call, now: start)
        _ = machine.update(processes: call, now: start.addingTimeInterval(1))
        machine.markRecording(bundleID: "us.zoom.xos")
        #expect(machine.update(processes: [], now: start.addingTimeInterval(2)).isEmpty)
        #expect(machine.update(processes: [], now: start.addingTimeInterval(6)).isEmpty)
        #expect(machine.update(processes: [], now: start.addingTimeInterval(7)) == [
            .callEnded(bundleID: "us.zoom.xos")
        ])
    }

    private func process(
        id: AudioObjectID = 7,
        bundleID: String = "us.zoom.xos",
        input: Bool,
        output: Bool
    ) -> AudioProcessSnapshot {
        AudioProcessSnapshot(
            objectID: id,
            pid: 99,
            bundleID: bundleID,
            isRunningInput: input,
            isRunningOutput: output
        )
    }
}
