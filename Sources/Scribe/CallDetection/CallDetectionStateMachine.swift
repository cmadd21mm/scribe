import CoreAudio
import Foundation

struct LiveCall: Equatable, Sendable {
    let bundleID: String
    let processObjectIDs: [AudioObjectID]
}

struct CallDetectionStateMachine: Sendable {
    enum Action: Equatable, Sendable {
        case prompt(LiveCall)
        case callEnded(bundleID: String)
    }

    private enum Phase: Sendable {
        case observing(since: Date)
        case prompted
        case declined
        case recording
    }

    private struct Entry: Sendable {
        var call: LiveCall
        var phase: Phase
        var missingSince: Date?
    }

    let promptAfter: TimeInterval
    let endAfter: TimeInterval
    private var entries: [String: Entry] = [:]

    init(promptAfter: TimeInterval = 8, endAfter: TimeInterval = 10) {
        self.promptAfter = promptAfter
        self.endAfter = endAfter
    }

    /// Detect calls when a configured app is actively using the microphone.
    /// Input and output may belong to different helper processes; the finder
    /// normalizes those helpers to one canonical app bundle ID first.
    mutating func update(processes: [AudioProcessSnapshot], now: Date) -> [Action] {
        let grouped = Dictionary(grouping: processes.filter { $0.bundleID != nil }) {
            $0.bundleID!
        }
        let eligible = grouped.filter { _, snapshots in
            snapshots.contains { $0.isRunningInput }
        }
        let calls = eligible.mapValues { snapshots in
            LiveCall(
                bundleID: snapshots[0].bundleID!,
                processObjectIDs: snapshots.map(\.objectID).sorted()
            )
        }

        var actions: [Action] = []
        for (bundleID, call) in calls {
            guard var entry = entries[bundleID] else {
                entries[bundleID] = Entry(
                    call: call,
                    phase: .observing(since: now),
                    missingSince: nil
                )
                continue
            }
            entry.call = call
            entry.missingSince = nil
            if case .observing(let since) = entry.phase,
               now.timeIntervalSince(since) >= promptAfter {
                entry.phase = .prompted
                actions.append(.prompt(call))
            }
            entries[bundleID] = entry
        }

        for bundleID in Array(entries.keys) where calls[bundleID] == nil {
            guard var entry = entries[bundleID] else { continue }
            if case .recording = entry.phase {
                if let missingSince = entry.missingSince {
                    if now.timeIntervalSince(missingSince) >= endAfter {
                        actions.append(.callEnded(bundleID: bundleID))
                        entries.removeValue(forKey: bundleID)
                    }
                } else {
                    entry.missingSince = now
                    entries[bundleID] = entry
                }
            } else {
                // A declined or unanswered prompt is suppressed until that
                // call actually ends; a later call may prompt again.
                entries.removeValue(forKey: bundleID)
            }
        }
        return actions
    }

    mutating func markRecording(bundleID: String) {
        guard var entry = entries[bundleID] else { return }
        entry.phase = .recording
        entry.missingSince = nil
        entries[bundleID] = entry
    }

    mutating func decline(bundleID: String) {
        guard var entry = entries[bundleID] else { return }
        entry.phase = .declined
        entries[bundleID] = entry
    }
}

enum LiveCallFinder {
    static func configuredCalls(
        in processes: [AudioProcessSnapshot],
        allowedBundleIDs: Set<String>,
        runningBundleIDs: Set<String> = []
    ) -> [AudioProcessSnapshot] {
        processes.compactMap { process in
            guard process.isRunningInput || process.isRunningOutput,
                  let bundleID = ConferenceAppMatcher.canonicalBundleID(
                    for: process.bundleID,
                    allowedBundleIDs: allowedBundleIDs,
                    runningBundleIDs: runningBundleIDs,
                    allowSharedAliases: true
                  )
            else { return nil }
            return AudioProcessSnapshot(
                objectID: process.objectID,
                pid: process.pid,
                bundleID: bundleID,
                isRunningInput: process.isRunningInput,
                isRunningOutput: process.isRunningOutput
            )
        }
    }
}
