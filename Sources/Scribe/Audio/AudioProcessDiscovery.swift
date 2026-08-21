import AppKit
import CoreAudio
import Foundation

/// The Core Audio properties Scribe needs, separated from discovery so process
/// selection stays deterministic and unit-testable without audio hardware.
struct AudioProcessSnapshot: Equatable, Sendable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningInput: Bool
    let isRunningOutput: Bool
}

enum AudioProcessSelector {
    /// Return active output processes that belong to a configured app. Helper
    /// processes are normalized back to the parent app's bundle ID so browser
    /// renderers and Electron audio services do not hide the meeting source.
    static func captureTargets(
        from processes: [AudioProcessSnapshot],
        allowedBundleIDs: Set<String>,
        runningBundleIDs: Set<String> = []
    ) -> [AudioProcessSnapshot] {
        processes
            .compactMap { process in
                guard process.isRunningOutput,
                      let bundleID = ConferenceAppMatcher.canonicalBundleID(
                        for: process.bundleID,
                        allowedBundleIDs: allowedBundleIDs,
                        runningBundleIDs: runningBundleIDs
                      )
                else { return nil }
                return process.with(bundleID: bundleID)
            }
            .sorted { lhs, rhs in
                if lhs.pid == rhs.pid { return lhs.objectID < rhs.objectID }
                return lhs.pid < rhs.pid
            }
    }
}

enum ConferenceAppMatcher {
    /// Helpers normally retain the parent bundle ID as a prefix. Apple routes
    /// Safari and FaceTime through shared services whose identifiers need an
    /// explicit alias.
    private static let helperAliases: [(prefix: String, parent: String)] = [
        ("com.apple.WebKit", "com.apple.Safari"),
        ("com.apple.avconferenced", "com.apple.FaceTime"),
    ]

    static func canonicalBundleID(
        for processBundleID: String?,
        allowedBundleIDs: Set<String>,
        runningBundleIDs: Set<String> = [],
        allowSharedAliases: Bool = false
    ) -> String? {
        guard let processBundleID, !processBundleID.isEmpty else { return nil }
        if allowedBundleIDs.contains(processBundleID) { return processBundleID }

        // Prefer the longest match if a user configured overlapping IDs.
        if let parent = allowedBundleIDs
            .sorted(by: { $0.count > $1.count })
            .first(where: {
                processBundleID.hasPrefix($0 + ".")
                    || processBundleID.hasPrefix($0 + "-")
            }) {
            return parent
        }

        guard allowSharedAliases else { return nil }
        for alias in helperAliases
        where allowedBundleIDs.contains(alias.parent)
            && runningBundleIDs.contains(alias.parent)
            && (processBundleID == alias.prefix
                || processBundleID.hasPrefix(alias.prefix + ".")) {
            return alias.parent
        }
        return nil
    }
}

private extension AudioProcessSnapshot {
    func with(bundleID: String) -> AudioProcessSnapshot {
        AudioProcessSnapshot(
            objectID: objectID,
            pid: pid,
            bundleID: bundleID,
            isRunningInput: isRunningInput,
            isRunningOutput: isRunningOutput
        )
    }
}

enum AudioProcessDiscovery {
    enum DiscoveryError: Error, CustomStringConvertible {
        case propertySize(AudioObjectPropertySelector, OSStatus)
        case propertyRead(AudioObjectPropertySelector, OSStatus)

        var description: String {
            switch self {
            case .propertySize(let selector, let status):
                return "Core Audio property \(selector) size failed (OSStatus \(status))"
            case .propertyRead(let selector, let status):
                return "Core Audio property \(selector) read failed (OSStatus \(status))"
            }
        }
    }

    static func snapshots() throws -> [AudioProcessSnapshot] {
        let ids = try processObjectIDs()
        return ids.compactMap { objectID in
            guard let pid: pid_t = scalarProperty(
                objectID: objectID,
                selector: kAudioProcessPropertyPID,
                initialValue: 0
            ) else { return nil }
            return AudioProcessSnapshot(
                objectID: objectID,
                pid: pid,
                bundleID: bundleID(for: objectID),
                isRunningInput: scalarProperty(
                    objectID: objectID,
                    selector: kAudioProcessPropertyIsRunningInput,
                    initialValue: UInt32(0)
                ).map { (value: UInt32) in value != 0 } ?? false,
                isRunningOutput: scalarProperty(
                    objectID: objectID,
                    selector: kAudioProcessPropertyIsRunningOutput,
                    initialValue: UInt32(0)
                ).map { (value: UInt32) in value != 0 } ?? false
            )
        }
    }

    static func runningApplicationBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private static func processObjectIDs() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else {
            throw DiscoveryError.propertySize(address.mSelector, status)
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        )
        guard status == noErr else {
            throw DiscoveryError.propertyRead(address.mSelector, status)
        }
        return ids
    }

    private static func scalarProperty<T: FixedWidthInteger>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        initialValue: T
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = initialValue
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func bundleID(for objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        let retained = value.takeRetainedValue()
        return retained as NSString as String
    }
}
