import CoreMedia
import Foundation

public struct RecordingTimeline: Sendable {
    private var timestampOffset: CMTime = .zero
    private var nextExpectedSampleTime: CMTime?
    private var pauseStartedAt: CMTime?

    public init() {}

    public mutating func reset() {
        timestampOffset = .zero
        nextExpectedSampleTime = nil
        pauseStartedAt = nil
    }

    public mutating func pause() {
        if pauseStartedAt == nil {
            pauseStartedAt = nextExpectedSampleTime
        }
    }

    public mutating func resume() {}

    public mutating func offsetForAppendedSample(
        presentationTime: CMTime,
        duration: CMTime
    ) -> CMTime {
        if let pauseStartedAt,
           let pausedDuration = Self.positiveDuration(from: pauseStartedAt, to: presentationTime) {
            timestampOffset = timestampOffset + pausedDuration
            self.pauseStartedAt = nil
        }

        let currentOffset = timestampOffset
        if presentationTime.isValid {
            if duration.isValid, CMTimeCompare(duration, .zero) > 0 {
                nextExpectedSampleTime = presentationTime + duration
            } else {
                nextExpectedSampleTime = presentationTime
            }
        }
        return currentOffset
    }

    private static func positiveDuration(from start: CMTime, to end: CMTime) -> CMTime? {
        guard start.isValid, end.isValid else {
            return nil
        }

        let duration = end - start
        guard duration.isValid, CMTimeCompare(duration, .zero) > 0 else {
            return nil
        }
        return duration
    }
}
