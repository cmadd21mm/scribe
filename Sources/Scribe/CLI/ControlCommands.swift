import AppKit
import ArgumentParser
import Foundation

enum ScribeControlNotification {
    static let start = Notification.Name("com.cmadd21mm.scribe.control.start")
    static let stop = Notification.Name("com.cmadd21mm.scribe.control.stop")
    static let quit = Notification.Name("com.cmadd21mm.scribe.control.quit")
}

private enum ControlClient {
    static func post(_ name: Notification.Name, userInfo: [String: Any]? = nil) {
        DistributedNotificationCenter.default().post(
            name: name,
            object: nil,
            userInfo: userInfo
        )
    }
}

struct StartRecording: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Ask the running Scribe app to start a recording."
    )

    @Option(name: .long, help: "Bundle ID to capture; repeat for multiple processes.")
    var bundleID: [String] = []

    @Option(name: .long, help: "Fallback title when no calendar event matches.")
    var title: String = "Manual meeting"

    func run() {
        var info: [String: Any] = ["title": title]
        if !bundleID.isEmpty { info["bundle_ids"] = bundleID }
        ControlClient.post(ScribeControlNotification.start, userInfo: info)
        print("recording request sent to Scribe")
    }
}

struct StopRecording: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Ask the running Scribe app to stop its recording."
    )

    func run() {
        ControlClient.post(ScribeControlNotification.stop)
        print("stop request sent to Scribe")
    }
}

struct QuitDaemon: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quit",
        abstract: "Ask the running Scribe app to stop cleanly and quit."
    )

    func run() {
        ControlClient.post(ScribeControlNotification.quit)
        print("quit request sent to Scribe")
    }
}

struct OpenRecordings: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open the configured recordings folder in Finder."
    )

    @Option(name: .long, help: "Override the configured recordings root.")
    var out: String?

    func run() throws {
        let root = Config.resolveRoot(cliOverride: out)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }
}

struct ListAudioApps: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "List processes currently using audio and their bundle IDs."
    )

    func run() throws {
        let configured = Config.callAppBundleIDs()
        let snapshots = try AudioProcessDiscovery.snapshots()
            .filter { $0.isRunningInput || $0.isRunningOutput }
            .sorted { $0.pid < $1.pid }
        if snapshots.isEmpty {
            print("no processes are currently using audio")
            return
        }
        for process in snapshots {
            let bundle = process.bundleID ?? "(no bundle ID)"
            let allowed = process.bundleID.map(configured.contains) == true ? "configured" : "manual"
            print("\(process.pid)\tinput=\(process.isRunningInput)\toutput=\(process.isRunningOutput)\t\(allowed)\t\(bundle)")
        }
    }
}
