import Foundation

public struct MeterReading: Equatable, Sendable {
    public let rms: Float
    public let peak: Float
    public let normalizedLevel: Float
    public let isSilent: Bool

    public static let silence = MeterReading(rms: 0, peak: 0, normalizedLevel: 0, isSilent: true)
}

public struct AudioMeter: Sendable {
    private let silenceThreshold: Float
    private let silenceReleaseCount: Int
    private var consecutiveSilentReadings = 0
    private var isCurrentlySilent = true

    public init(silenceThreshold: Float = 0.002, silenceReleaseCount: Int = 12) {
        self.silenceThreshold = silenceThreshold
        self.silenceReleaseCount = max(1, silenceReleaseCount)
    }

    public mutating func process(samples: [Float]) -> MeterReading {
        guard !samples.isEmpty else {
            isCurrentlySilent = true
            consecutiveSilentReadings = silenceReleaseCount
            return .silence
        }

        var sumSquares: Float = 0
        var peak: Float = 0

        for sample in samples {
            let absolute = abs(sample)
            peak = max(peak, absolute)
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(samples.count))
        let normalized = min(max(peak, 0), 1)
        let rawSilent = peak < silenceThreshold && rms < silenceThreshold

        if rawSilent {
            if !isCurrentlySilent {
                consecutiveSilentReadings += 1
                if consecutiveSilentReadings >= silenceReleaseCount {
                    isCurrentlySilent = true
                }
            }
        } else {
            isCurrentlySilent = false
            consecutiveSilentReadings = 0
        }

        return MeterReading(
            rms: rms,
            peak: peak,
            normalizedLevel: normalized,
            isSilent: isCurrentlySilent
        )
    }
}
