/// Give people time to speak before playing the Mac-audio chime.
/// Retry once if the tap has not detected any Mac audio yet.
enum AudioSetupGuide {
    static let duration = 15
    static let chimeRemainingSeconds = 7

    static func shouldPlayChime(remainingSeconds: Int, systemHasSignal: Bool) -> Bool {
        remainingSeconds == chimeRemainingSeconds || (remainingSeconds == 4 && !systemHasSignal)
    }

    static func instruction(remainingSeconds: Int) -> String {
        remainingSeconds > chimeRemainingSeconds
            ? "Say: “Scribe helps me remember the important parts of my meetings.”"
            : "Listen for a short chime. Scribe is checking Mac audio automatically."
    }
}
