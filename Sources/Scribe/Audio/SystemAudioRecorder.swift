@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os.lock

/// Records system audio output to a file via a Core Audio process tap
/// (macOS 14.2+). No virtual device, no kernel extension — the tap mixes the
/// requested output to stereo and hands us buffers through a private aggregate
/// device. First use triggers the one-time "System Audio Recording" TCC prompt
/// and lights the purple recording indicator while active.
final class SystemAudioRecorder {
    enum CaptureScope: Equatable {
        case processes([AudioObjectID])
        case allSystemAudio(excluding: [AudioObjectID])
    }

    enum RecorderError: Error, CustomStringConvertible {
        case tapCreationFailed(OSStatus)
        case tapFormatUnreadable(OSStatus)
        case aggregateCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)
        case fileCreationFailed(Error)
        case noEligibleProcesses

        var description: String {
            switch self {
            case .tapCreationFailed(let s):
                return "process tap creation failed (OSStatus \(s)) — check System Settings → Privacy & Security → Screen & System Audio Recording"
            case .tapFormatUnreadable(let s): return "couldn't read tap stream format (OSStatus \(s))"
            case .aggregateCreationFailed(let s): return "aggregate device creation failed (OSStatus \(s))"
            case .ioProcCreationFailed(let s): return "IO proc creation failed (OSStatus \(s))"
            case .deviceStartFailed(let s): return "device start failed (OSStatus \(s))"
            case .fileCreationFailed(let e): return "output file creation failed: \(e)"
            case .noEligibleProcesses:
                return "no configured call app is currently producing audio; add its bundle ID to call_apps or start the call first"
            }
        }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.cmadd21mm.scribe.system-tap")
    private(set) var isRecording = false

    private struct LockedState {
        var file: AVAudioFile?
        var firstBufferAt: Date?
        var lastBufferAt: Date?
        var capturedFrames: Int64 = 0
        var peak: Float = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: LockedState())

    private var file: AVAudioFile? {
        get { state.withLock { $0.file } }
        set { state.withLock { $0.file = newValue } }
    }
    /// Wall-clock time of the first captured buffer — the track's true start,
    /// used to offset-align the two tracks' transcript timestamps.
    private(set) var firstBufferAt: Date? {
        get { state.withLock { $0.firstBufferAt } }
        set { state.withLock { $0.firstBufferAt = newValue } }
    }

    private(set) var lastBufferAt: Date? {
        get { state.withLock { $0.lastBufferAt } }
        set { state.withLock { $0.lastBufferAt = newValue } }
    }

    var signalStatus: AudioSignalStatus {
        state.withLock {
            AudioSignalStatus(capturedFrames: $0.capturedFrames, peak: $0.peak)
        }
    }

    /// Start capturing system audio, encoding AAC into `url` (use a .caf
    /// extension — CAF needs no finalization pass, so a crash mid-meeting
    /// loses nothing already written).
    func start(writingTo url: URL, scope: CaptureScope) throws {
        guard !isRecording else { return }

        let description: CATapDescription
        switch scope {
        case .processes(let processObjectIDs):
            guard !processObjectIDs.isEmpty else { throw RecorderError.noEligibleProcesses }
            description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        case .allSystemAudio(let excludedProcessObjectIDs):
            description = CATapDescription(
                stereoGlobalTapButExcludeProcesses: excludedProcessObjectIDs
            )
        }
        description.name = "Scribe system tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        state.withLock {
            $0.firstBufferAt = nil
            $0.lastBufferAt = nil
            $0.capturedFrames = 0
            $0.peak = 0
        }

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw RecorderError.tapCreationFailed(status) }
        tapID = newTapID

        do {
            let format = try tapStreamFormat()
            try createAggregateDevice(tapUUID: description.uuid)
            file = try makeFile(url: url, format: format)
            try installIOProc(format: format)
        } catch {
            cleanup()
            throw error
        }

        isRecording = true
    }

    /// Stop capturing and finalize the file. Idempotent.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
        }
        cleanup()
    }

    // MARK: -

    private func tapStreamFormat() throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw RecorderError.tapFormatUnreadable(status)
        }
        return format
    }

    private func createAggregateDevice(tapUUID: UUID) throws {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "scribe-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newAggregateID)
        guard status == noErr else { throw RecorderError.aggregateCreationFailed(status) }
        aggregateID = newAggregateID
    }

    private func makeFile(url: URL, format: AVAudioFormat) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ]
        do {
            return try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            throw RecorderError.fileCreationFailed(error)
        }
    }

    private func installIOProc(format: AVAudioFormat) throws {
        var status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self, let file = self.file else { return }
            let now = Date()
            self.state.withLock {
                if $0.firstBufferAt == nil { $0.firstBufferAt = now }
                $0.lastBufferAt = now
            }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: inInputData,
                deallocator: nil
            ) else { return }
            let peak = AudioSignalStatus.peak(in: buffer)
            self.state.withLock {
                $0.capturedFrames += Int64(buffer.frameLength)
                $0.peak = max($0.peak, peak)
            }
            do {
                try file.write(from: buffer)
            } catch {
                FileHandle.standardError.write(Data("system track write failed: \(error)\n".utf8))
            }
        }
        guard status == noErr, let procID else { throw RecorderError.ioProcCreationFailed(status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw RecorderError.deviceStartFailed(status) }
    }

    private func cleanup() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        file = nil
        lastBufferAt = nil
    }
}
