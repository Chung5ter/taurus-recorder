import Foundation

public enum RecordingInputMode: String, CaseIterable, Identifiable, Sendable {
    case computer

    public var id: String { rawValue }

    public static let selectableCases: [RecordingInputMode] = [.computer]

    public var isSelectable: Bool {
        Self.selectableCases.contains(self)
    }

    public var displayName: String {
        switch self {
        case .computer:
            "Computer"
        }
    }

    public var capturesComputerAudio: Bool {
        true
    }
}

public struct InputGain: Equatable, Sendable {
    public static let notchedMultipliers: [Float] = [
        Float(1.0 / 3.0),
        0.5,
        0.75,
        1,
        1.5,
        2,
        3
    ]
    public static let minimumMultiplier = notchedMultipliers[0]
    public static let maximumMultiplier = notchedMultipliers[notchedMultipliers.count - 1]
    public static let minimumNotchIndex = 0
    public static let maximumNotchIndex = notchedMultipliers.count - 1
    public static let unity = InputGain(multiplier: 1)

    public let multiplier: Float

    public init(multiplier: Float) {
        self.multiplier = Self.notchedMultiplier(closestTo: multiplier)
    }

    public init(notchIndex: Int) {
        self.multiplier = Self.multiplier(forNotchIndex: notchIndex)
    }

    public var notchIndex: Int {
        Self.notchIndex(closestTo: multiplier)
    }

    public static func multiplier(forNotchIndex notchIndex: Int) -> Float {
        let clampedIndex = min(max(notchIndex, minimumNotchIndex), maximumNotchIndex)
        return notchedMultipliers[clampedIndex]
    }

    public static func notchIndex(closestTo multiplier: Float) -> Int {
        notchedMultipliers.indices.min { lhs, rhs in
            abs(notchedMultipliers[lhs] - multiplier) < abs(notchedMultipliers[rhs] - multiplier)
        } ?? minimumNotchIndex
    }

    public static func notchedMultiplier(closestTo multiplier: Float) -> Float {
        Self.multiplier(forNotchIndex: notchIndex(closestTo: multiplier))
    }

    public var decibels: Float {
        20 * log10(multiplier)
    }

    public var decibelLabel: String {
        let value = decibels
        if abs(value) < 0.05 {
            return "0.0 dB"
        }
        return String(format: "%+.1f dB", value)
    }
}

public enum AudioCaptureTarget: Equatable, Hashable, Sendable {
    case allComputerAudio
    case application(bundleIdentifier: String, displayName: String)

    public var displayName: String {
        switch self {
        case .allComputerAudio:
            "All Computer Audio"
        case .application(_, let displayName):
            displayName
        }
    }

    public var bundleIdentifier: String? {
        switch self {
        case .allComputerAudio:
            nil
        case .application(let bundleIdentifier, _):
            bundleIdentifier
        }
    }
}

public struct AudioCaptureSettings: Equatable, Sendable {
    public var target: AudioCaptureTarget
    public var inputGain: InputGain

    public init(target: AudioCaptureTarget = .allComputerAudio, inputGain: InputGain = .unity) {
        self.target = target
        self.inputGain = inputGain
    }
}
