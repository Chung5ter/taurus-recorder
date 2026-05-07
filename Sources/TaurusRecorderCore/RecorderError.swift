import Foundation

public enum RecorderError: LocalizedError {
    case screenRecordingPermissionNeeded
    case microphonePermissionNeeded
    case captureSetupFailed(String)
    case microphoneCaptureUnsupported
    case noDisplayAvailable
    case streamOutputRegistrationFailed(String)
    case unsupportedAudioBuffer
    case writerNotReady
    case writerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionNeeded:
            "Allow Taurus Recorder in Screen & System Audio Recording. If it is already enabled, turn it off and back on, then quit and reopen Taurus Recorder."
        case .microphonePermissionNeeded:
            "Allow Taurus Recorder in Microphone to record your mic."
        case .captureSetupFailed(let message):
            "Could not prepare system audio capture: \(message)"
        case .microphoneCaptureUnsupported:
            "Microphone recording requires macOS 15 or later."
        case .noDisplayAvailable:
            "No display is available for ScreenCaptureKit audio capture."
        case .streamOutputRegistrationFailed(let message):
            "Could not start audio capture: \(message)"
        case .unsupportedAudioBuffer:
            "The system audio buffer format could not be read."
        case .writerNotReady:
            "The audio file writer is not ready."
        case .writerFailed(let message):
            "Could not save the recording: \(message)"
        }
    }
}
