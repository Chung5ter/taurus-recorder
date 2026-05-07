import Foundation

public enum RecorderError: LocalizedError {
    case screenRecordingPermissionNeeded
    case captureSetupFailed(String)
    case noDisplayAvailable
    case streamOutputRegistrationFailed(String)
    case unsupportedAudioBuffer
    case writerNotReady
    case writerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionNeeded:
            "Screen Recording permission is needed before Taurus Recorder can capture system audio."
        case .captureSetupFailed(let message):
            "Could not prepare system audio capture: \(message)"
        case .noDisplayAvailable:
            "No display is available for ScreenCaptureKit audio capture."
        case .streamOutputRegistrationFailed(let message):
            "Could not start system audio monitoring: \(message)"
        case .unsupportedAudioBuffer:
            "The system audio buffer format could not be read."
        case .writerNotReady:
            "The audio file writer is not ready."
        case .writerFailed(let message):
            "Could not save the recording: \(message)"
        }
    }
}
