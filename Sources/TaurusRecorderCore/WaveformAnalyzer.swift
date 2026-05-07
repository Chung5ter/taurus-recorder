import Foundation

public struct WaveformPoint: Equatable, Sendable {
    public let minimum: Float
    public let maximum: Float

    public init(minimum: Float, maximum: Float) {
        self.minimum = max(-1, min(1, minimum))
        self.maximum = max(-1, min(1, maximum))
    }
}

public struct WaveformAnalyzer: Sendable {
    public private(set) var points: [WaveformPoint] = []

    private let maxPoints: Int
    private let samplesPerPoint: Int
    private var pendingSamples: [Float] = []

    public init(maxPoints: Int = 720, samplesPerPoint: Int = 512) {
        precondition(maxPoints > 0 && samplesPerPoint > 0)
        self.maxPoints = maxPoints
        self.samplesPerPoint = samplesPerPoint
    }

    public mutating func reset() {
        points.removeAll(keepingCapacity: true)
        pendingSamples.removeAll(keepingCapacity: true)
    }

    public mutating func process(samples: [Float]) {
        guard !samples.isEmpty else {
            return
        }

        pendingSamples.append(contentsOf: samples)

        while pendingSamples.count >= samplesPerPoint {
            let chunk = pendingSamples.prefix(samplesPerPoint)
            let minimum = chunk.min() ?? 0
            let maximum = chunk.max() ?? 0
            append(WaveformPoint(minimum: minimum, maximum: maximum))
            pendingSamples.removeFirst(samplesPerPoint)
        }
    }

    private mutating func append(_ point: WaveformPoint) {
        points.append(point)
        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }
    }
}
