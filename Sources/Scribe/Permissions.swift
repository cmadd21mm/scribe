import AVFoundation
import Foundation

enum Permissions {
    static let microphoneSettingsMessage = "Microphone access is required. Enable Scribe in System Settings → Privacy & Security → Microphone."
    static let systemAudioSettingsMessage = "System audio access is required. Enable Scribe in System Settings → Privacy & Security → Screen & System Audio Recording."

    static var microphoneIsDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .denied || status == .restricted
    }
}
