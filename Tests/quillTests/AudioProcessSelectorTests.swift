import CoreAudio
import Testing

@testable import quill

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
