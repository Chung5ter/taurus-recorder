import Foundation

public struct PlaybackTimeline: Sendable {
    public let duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = max(0, duration)
    }

    public func time(afterSkipping delta: TimeInterval, from currentTime: TimeInterval) -> TimeInterval {
        min(max(0, currentTime + delta), duration)
    }

    public func progress(at currentTime: TimeInterval) -> Double {
        guard duration > 0 else {
            return 0
        }
        return min(max(currentTime / duration, 0), 1)
    }

    public func time(atProgress progress: Double) -> TimeInterval {
        guard duration > 0 else {
            return 0
        }
        return min(max(progress, 0), 1) * duration
    }
}
