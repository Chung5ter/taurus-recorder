import Foundation

public enum RecordingState: Equatable, Sendable {
    case idle
    case recording
    case paused
    case saving
    case error(String)

    public var title: String {
        switch self {
        case .idle:
            "Idle"
        case .recording:
            "Recording"
        case .paused:
            "Paused"
        case .saving:
            "Saving"
        case .error:
            "Error"
        }
    }
}
