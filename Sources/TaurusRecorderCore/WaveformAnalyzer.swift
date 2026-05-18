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
    public var points: [WaveformPoint] {
        guard pointCount > 0 else {
            return []
        }

        if pointCount < maxPoints {
            return Array(pointStorage[..<pointCount])
        }

        var orderedPoints: [WaveformPoint] = []
        orderedPoints.reserveCapacity(pointCount)
        orderedPoints.append(contentsOf: pointStorage[nextPointIndex...])
        orderedPoints.append(contentsOf: pointStorage[..<nextPointIndex])
        return orderedPoints
    }

    private let maxPoints: Int
    private let samplesPerPoint: Int
    private var pointStorage: [WaveformPoint]
    private var pointCount = 0
    private var nextPointIndex = 0
    private var currentMinimum: Float = 1
    private var currentMaximum: Float = -1
    private var currentSampleCount = 0

    public init(maxPoints: Int = 720, samplesPerPoint: Int = 512) {
        precondition(maxPoints > 0 && samplesPerPoint > 0)
        self.maxPoints = maxPoints
        self.samplesPerPoint = samplesPerPoint
        self.pointStorage = Array(repeating: WaveformPoint(minimum: 0, maximum: 0), count: maxPoints)
    }

    public mutating func reset() {
        pointCount = 0
        nextPointIndex = 0
        currentMinimum = 1
        currentMaximum = -1
        currentSampleCount = 0
    }

    public mutating func process(samples: [Float]) {
        guard !samples.isEmpty else {
            return
        }

        for sample in samples {
            currentMinimum = min(currentMinimum, sample)
            currentMaximum = max(currentMaximum, sample)
            currentSampleCount += 1

            if currentSampleCount == samplesPerPoint {
                append(WaveformPoint(minimum: currentMinimum, maximum: currentMaximum))
                currentMinimum = 1
                currentMaximum = -1
                currentSampleCount = 0
            }
        }
    }

    private mutating func append(_ point: WaveformPoint) {
        pointStorage[nextPointIndex] = point
        nextPointIndex = (nextPointIndex + 1) % maxPoints
        pointCount = min(pointCount + 1, maxPoints)
    }
}
