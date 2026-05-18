import Foundation

public struct VisualUpdateThrottle: Sendable {
    private let interval: TimeInterval
    private var nextPublishTime: TimeInterval = 0

    public init(interval: TimeInterval) {
        self.interval = max(interval, 0)
    }

    public mutating func reset() {
        nextPublishTime = 0
    }

    public mutating func shouldPublish(at time: TimeInterval) -> Bool {
        guard time >= nextPublishTime else {
            return false
        }
        nextPublishTime = time + interval
        return true
    }
}
