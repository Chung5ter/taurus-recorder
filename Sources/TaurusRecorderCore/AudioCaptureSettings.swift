import Foundation

public enum RecordingInputMode: String, CaseIterable, Identifiable, Sendable {
    case computer
    case computerAndMicrophone
    case microphone

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .computer:
            "Computer"
        case .computerAndMicrophone:
            "Computer + Mic"
        case .microphone:
            "Mic"
        }
    }

    public var capturesComputerAudio: Bool {
        self == .computer || self == .computerAndMicrophone
    }

    public var capturesMicrophone: Bool {
        self == .microphone || self == .computerAndMicrophone
    }
}

public struct InputGain: Equatable, Sendable {
    public static let minimumMultiplier = Float(1.0 / 3.0)
    public static let maximumMultiplier = Float(3.0)
    public static let unity = InputGain(multiplier: 1)

    public let multiplier: Float

    public init(multiplier: Float) {
        self.multiplier = min(max(multiplier, Self.minimumMultiplier), Self.maximumMultiplier)
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

public struct AudioCaptureSettings: Equatable, Sendable {
    public var inputMode: RecordingInputMode
    public var inputGain: InputGain

    public init(inputMode: RecordingInputMode = .computer, inputGain: InputGain = .unity) {
        self.inputMode = inputMode
        self.inputGain = inputGain
    }
}
