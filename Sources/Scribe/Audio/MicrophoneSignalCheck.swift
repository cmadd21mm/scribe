/// Keeps measuring the whole recording after the startup silence check settles.
/// A user may begin speaking after that initial two-second window.
struct MicrophoneSignalCheck {
    private(set) var capturedFrames: Int64 = 0
    private(set) var peak: Float = 0
    private var startupCheckFinished = false

    var status: AudioSignalStatus {
        AudioSignalStatus(capturedFrames: capturedFrames, peak: peak)
    }

    /// Returns true once if the initial two seconds contain only digital silence.
    mutating func observe(frameCount: Int, peak: Float, sampleRate: Double) -> Bool {
        capturedFrames += Int64(frameCount)
        self.peak = max(self.peak, peak)
        guard !startupCheckFinished, capturedFrames >= Int64(sampleRate * 2) else { return false }
        startupCheckFinished = true
        return !status.hasSignal
    }
}
