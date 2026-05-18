import Foundation

public enum RecorderError: LocalizedError {
    case systemAudioRecordingPermissionNeeded
    case captureSetupFailed(String)
    case targetApplicationUnavailable(String)
    case unsupportedAudioBuffer
    case writerNotReady
    case writerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .systemAudioRecordingPermissionNeeded:
            "Allow Taurus Recorder in System Audio Recording Only. If it is already enabled, turn it off and back on, then quit and reopen Taurus Recorder."
        case .captureSetupFailed(let message):
            "Could not prepare system audio capture: \(message)"
        case .targetApplicationUnavailable(let displayName):
            "\(displayName) is not available to record. Open the app, then refresh the source list and try again."
        case .unsupportedAudioBuffer:
            "The system audio buffer format could not be read."
        case .writerNotReady:
            "The audio file writer is not ready."
        case .writerFailed(let message):
            "Could not save the recording: \(message)"
        }
    }
}
