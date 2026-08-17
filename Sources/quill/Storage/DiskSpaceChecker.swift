import Foundation

enum DiskSpacePolicy {
    static func hasEnoughSpace(availableBytes: Int64, minimumBytes: Int64) -> Bool {
        availableBytes >= minimumBytes
    }
}

enum DiskSpaceChecker {
    struct InsufficientSpace: Error, CustomStringConvertible {
        let availableBytes: Int64
        let minimumBytes: Int64

        var description: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "not enough free disk space: \(formatter.string(fromByteCount: availableBytes)) available; Quill requires \(formatter.string(fromByteCount: minimumBytes)) before recording"
        }
    }

    static func requireSpace(at root: URL, minimumBytes: Int64) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else {
            throw CocoaError(.fileReadUnknown)
        }
        guard DiskSpacePolicy.hasEnoughSpace(
            availableBytes: available,
            minimumBytes: minimumBytes
        ) else {
            throw InsufficientSpace(availableBytes: available, minimumBytes: minimumBytes)
        }
    }
}
