import AVFoundation
import Foundation

enum Permissions {
    static let microphoneSettingsMessage = "Microphone access is required. Enable Scribe in System Settings → Privacy & Security → Microphone."
    static let systemAudioSettingsMessage = "System audio access is required. Enable Scribe in System Settings → Privacy & Security → Screen & System Audio Recording."

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
