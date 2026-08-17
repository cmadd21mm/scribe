import CoreAudio
import Foundation

/// The Core Audio properties Quill needs, separated from discovery so process
/// selection stays deterministic and unit-testable without audio hardware.
struct AudioProcessSnapshot: Equatable, Sendable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningInput: Bool
    let isRunningOutput: Bool
}

enum AudioProcessSelector {
    /// Return only active output processes whose bundle IDs are explicitly
    /// allowed. Quill never falls back to a global tap.
    static func captureTargets(
        from processes: [AudioProcessSnapshot],
        allowedBundleIDs: Set<String>
    ) -> [AudioProcessSnapshot] {
        processes
            .filter { process in
                process.isRunningOutput
                    && process.bundleID.map(allowedBundleIDs.contains) == true
            }
            .sorted { lhs, rhs in
                if lhs.pid == rhs.pid { return lhs.objectID < rhs.objectID }
                return lhs.pid < rhs.pid
            }
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
