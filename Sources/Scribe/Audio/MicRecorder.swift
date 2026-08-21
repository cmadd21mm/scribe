@preconcurrency import AVFoundation
import Foundation
import os.lock

/// Records the default input device to a file via AVAudioEngine, encoding AAC
/// mono. Buffers stream straight to disk — nothing is held in memory, so
/// session length is unbounded.
///
/// With voice processing on (the default), Apple's echo canceller subtracts
/// speaker playback from the mic so the system track doesn't bleed into the
/// mic track. VoiceProcessingIO is a duplex unit, not an input effect: it
/// needs a rendered output path and one explicit mono client format on both
/// sides, or it silently delivers zeroed buffers (rca-001). A first-second
/// liveness check catches routes where even the correct graph stays silent
/// and restarts capture raw.
final class MicRecorder: @unchecked Sendable {
    private final class SendableAudioBuffer: @unchecked Sendable {
        let value: AVAudioPCMBuffer

        init(_ value: AVAudioPCMBuffer) {
            self.value = value
        }
    }
    enum RecorderError: Error, CustomStringConvertible {
        case engineStartFailed(Error)
        case fileCreationFailed(Error)
        case formatUnsupported(AVAudioFormat)

        var description: String {
            switch self {
            case .engineStartFailed(let e): return "mic engine start failed: \(e)"
            case .fileCreationFailed(let e): return "mic file creation failed: \(e)"
            case .formatUnsupported(let f): return "can't downmix mic format \(f)"
            }
        }
    }

    private var engine = AVAudioEngine()
    private var url: URL?
    private(set) var isRecording = false
    private var configObserver: NSObjectProtocol?
    private var restartPending = false

    private struct LockedState {
        var file: AVAudioFile?
        var firstBufferAt: Date?
        var lastBufferAt: Date?
        var livenessFrames = 0
        var livenessPeak: Float = 0
        var livenessSettled = false
        var silenceRecoveryAttempted = false
        var unrecoverableSilence = false
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

    private var lastBufferAt: Date? {
        get { state.withLock { $0.lastBufferAt } }
        set { state.withLock { $0.lastBufferAt = newValue } }
    }

    var signalStatus: AudioSignalStatus {
        state.withLock {
            AudioSignalStatus(capturedFrames: Int64($0.livenessFrames), peak: $0.livenessPeak)
        }
    }

    /// Start capturing the mic, encoding AAC into `url` (use a .caf extension
    /// — CAF needs no finalization pass, so a crash loses nothing written).
    func start(writingTo url: URL) throws {
        guard !isRecording else { return }
        self.url = url
        state.withLock {
            $0.firstBufferAt = nil
            $0.lastBufferAt = nil
            $0.livenessFrames = 0
            $0.livenessPeak = 0
            $0.livenessSettled = false
            $0.silenceRecoveryAttempted = false
            $0.unrecoverableSilence = false
        }
        try attach(voiceProcessing: Config.micVoiceProcessing())
        isRecording = true
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, (notification.object as? AVAudioEngine) === self.engine else { return }
            self.handleConfigChange()
        }
    }

    /// Stop capturing and finalize the file. Idempotent.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        state.withLock {
            $0.file = nil
            $0.lastBufferAt = nil
        }
    }

    // MARK: -

    /// Build the engine graph, create the AAC file, and start capture. Called
    /// once at start, and a second time (voiceProcessing: false) if the
    /// liveness check trips.
    private func attach(voiceProcessing: Bool, reusingFile: Bool = false) throws {
        engine = AVAudioEngine()
        let input = engine.inputNode

        var voice = voiceProcessing
        state.withLock {
            $0.livenessFrames = 0
            $0.livenessPeak = 0
            $0.livenessSettled = false
        }

        if voice {
            do {
                try input.setVoiceProcessingEnabled(true)
                // The live voice unit makes macOS treat the session like a
                // call and duck all other audio — meetings played through the
                // speakers would get quieter the moment recording starts.
                input.voiceProcessingOtherAudioDuckingConfiguration =
                    .init(enableAdvancedDucking: false, duckingLevel: .min)
            } catch {
                FileHandle.standardError.write(Data(
                    "warning: mic voice processing unavailable (\(error)) — recording raw mic\n".utf8
                ))
                voice = false
            }
        }
        let inputFormat = input.outputFormat(forBus: 0)

        // One explicit mono client format. With voice processing this is the
        // Voice I/O boundary format on both sides of the duplex unit — never
        // accept the inherited multichannel route format (a 9-channel device
        // yielded digital silence). Raw capture downmixes to the same shape;
        // speech models want one channel anyway.
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.formatUnsupported(inputFormat)
        }

        if reusingFile, let existing = file {
            try installRawTap(
                on: input,
                inputFormat: inputFormat,
                monoFormat: existing.processingFormat
            )
            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                throw RecorderError.engineStartFailed(error)
            }
            return
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: monoFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        do {
            file = try AVAudioFile(
                forWriting: url!,
                settings: settings,
                commonFormat: monoFormat.commonFormat,
                interleaved: monoFormat.isInterleaved
            )
        } catch {
            throw RecorderError.fileCreationFailed(error)
        }

        if voice {
            // Complete the duplex graph: VoiceProcessingIO must render to an
            // output device or the input side never produces audio. The mixer
            // has no sources — nothing is monitored or played — its connection
            // exists solely to give the unit a formatted output path.
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: monoFormat)
            installVoiceTap(on: input, format: monoFormat)
        } else {
            try installRawTap(on: input, inputFormat: inputFormat, monoFormat: monoFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            file = nil
            throw RecorderError.engineStartFailed(error)
        }

        let report = "mic: voiceProcessing=\(input.isVoiceProcessingEnabled) "
            + "input=\(input.outputFormat(forBus: 0)) tap=\(monoFormat)\n"
        FileHandle.standardError.write(Data(report.utf8))
    }

    /// Voice-processing path: the unit converts to the mono client format
    /// itself, so tapped buffers write straight to the file. Tracks signal
    /// peak over the first two seconds — an unsupported route (device pair, macOS
    /// AUVPAggregate defects) delivers callbacks full of digital zeros, and
    /// the only recovery is restarting raw.
    private func installVoiceTap(on input: AVAudioInputNode, format: AVAudioFormat) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let file = self.file else { return }
            let now = Date()
            self.state.withLock {
                if $0.firstBufferAt == nil { $0.firstBufferAt = now }
                $0.lastBufferAt = now
            }

            let action = self.observeLiveness(buffer, sampleRate: format.sampleRate)
            if action == .recover {
                DispatchQueue.main.async { self.recoverFromSilence(currentlyUsingVoice: true) }
                return
            }

            do {
                try file.write(from: buffer)
            } catch {
                FileHandle.standardError.write(Data("mic track write failed: \(error)\n".utf8))
            }
        }
    }

    /// Raw path: tap at the device's native format and downmix to mono. Same
    /// sample rate on both sides, so the one-shot convert applies.
    private func installRawTap(
        on input: AVAudioInputNode,
        inputFormat: AVAudioFormat,
        monoFormat: AVAudioFormat
    ) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: monoFormat) else {
            throw RecorderError.formatUnsupported(inputFormat)
        }
        let sameRate = inputFormat.sampleRate == monoFormat.sampleRate
        let ratio = monoFormat.sampleRate / inputFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let file = self.file else { return }
            let now = Date()
            self.state.withLock {
                if $0.firstBufferAt == nil { $0.firstBufferAt = now }
                $0.lastBufferAt = now
            }
            let capacity = AVAudioFrameCount(Double(buffer.frameCapacity) * ratio) + 64
            guard let mono = AVAudioPCMBuffer(
                pcmFormat: monoFormat,
                frameCapacity: capacity
            ) else { return }
            do {
                if sameRate {
                    try converter.convert(to: mono, from: buffer)
                } else {
                    let source = SendableAudioBuffer(buffer)
                    let fed = OSAllocatedUnfairLock(initialState: false)
                    var conversionError: NSError?
                    converter.convert(to: mono, error: &conversionError) { _, status in
                        let shouldFeed = fed.withLock { value in
                            guard !value else { return false }
                            value = true
                            return true
                        }
                        if !shouldFeed {
                            status.pointee = .noDataNow
                            return nil
                        }
                        status.pointee = .haveData
                        return source.value
                    }
                    if let conversionError { throw conversionError }
                }
                let action = self.observeLiveness(mono, sampleRate: monoFormat.sampleRate)
                if action == .recover {
                    DispatchQueue.main.async {
                        self.recoverFromSilence(currentlyUsingVoice: false)
                    }
                    return
                }
                try file.write(from: mono)
            } catch {
                FileHandle.standardError.write(Data("mic track write failed: \(error)\n".utf8))
            }
        }
    }

    private enum LivenessAction {
        case none
        case recover
        case failed
    }

    /// Observe every mic path, including raw capture. FaceTime can leave the
    /// default input route connected while returning buffers made entirely of
    /// digital zero. Two seconds is long enough to identify that broken route;
    /// an idle physical microphone still has a measurable noise floor.
    private func observeLiveness(
        _ buffer: AVAudioPCMBuffer,
        sampleRate: Double
    ) -> LivenessAction {
        let peak = AudioSignalStatus.peak(in: buffer)
        return state.withLock { state in
            guard !state.livenessSettled else { return .none }
            state.livenessFrames += Int(buffer.frameLength)
            state.livenessPeak = max(state.livenessPeak, peak)
            guard state.livenessFrames >= Int(sampleRate * 2) else { return .none }
            state.livenessSettled = true
            guard state.livenessPeak <= 0.000_001 else { return .none }
            if !state.silenceRecoveryAttempted {
                state.silenceRecoveryAttempted = true
                return .recover
            }
            state.unrecoverableSilence = true
            return .failed
        }
    }

    /// Restart capture when Zoom, Teams, Meet, FaceTime, or another call app
    /// changes the active input route after a session has already begun.
    private func handleConfigChange() {
        guard isRecording, !restartPending else { return }
        restartPending = true
        FileHandle.standardError.write(Data(
            "mic: input device reconfigured — restarting capture\n".utf8
        ))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.restartCapture()
        }
    }

    private func restartCapture() {
        restartPending = false
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        padGapWithSilence()
        do {
            try attach(voiceProcessing: false, reusingFile: true)
        } catch {
            FileHandle.standardError.write(Data(
                "mic restart failed: \(error) — retrying in 2s\n".utf8
            ))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.isRecording else { return }
                self.restartCapture()
            }
        }
    }

    /// Preserve the meeting clock across a route-change interruption so
    /// transcript timestamps remain aligned with the system-audio track.
    private func padGapWithSilence() {
        let snapshot = state.withLock { ($0.file, $0.lastBufferAt) }
        guard let file = snapshot.0, let last = snapshot.1 else { return }
        let gap = Date().timeIntervalSince(last)
        guard gap > 0.05 else { return }

        let format = file.processingFormat
        var remaining = AVAudioFrameCount(gap * format.sampleRate)
        let chunk = AVAudioFrameCount(format.sampleRate)
        while remaining > 0 {
            let count = min(remaining, chunk)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                return
            }
            buffer.frameLength = count
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    channels[channel].update(repeating: 0, count: Int(count))
                }
            }
            try? file.write(from: buffer)
            remaining -= count
        }
    }

    /// A route delivered digital silence. Retry once using the other capture
    /// mode: raw → VoiceProcessingIO is important for FaceTime's aggregate
    /// device, while VoiceProcessingIO → raw remains the safest recovery for
    /// ordinary hardware and third-party meeting apps.
    private func recoverFromSilence(currentlyUsingVoice: Bool) {
        guard isRecording else { return }
        FileHandle.standardError.write(Data(
            "warning: mic delivered digital silence — retrying "
                .appending(currentlyUsingVoice ? "raw\n" : "with voice processing\n").utf8
        ))
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        state.withLock {
            $0.file = nil
            $0.firstBufferAt = nil
            $0.lastBufferAt = nil
        }
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        do {
            try attach(voiceProcessing: !currentlyUsingVoice)
        } catch {
            FileHandle.standardError.write(Data(
                "mic silence recovery failed: \(error) — capture health check will report it\n".utf8
            ))
            file = nil
            state.withLock { $0.unrecoverableSilence = true }
        }
    }
}
