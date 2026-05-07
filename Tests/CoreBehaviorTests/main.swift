import Foundation
import CoreMedia
import TaurusRecorderCore

@main
struct CoreBehaviorTests {
    static func main() throws {
        try testFileNamingCreatesFirstDefaultName()
        try testFileNamingIncrementsExistingNames()
        testInputGainUsesThreeTimesRangeAndDecibelLabels()
        testRecordingInputModeLabels()
        testMeterDetectsSilence()
        testMeterDetectsActiveSignal()
        testMP3FormatIsAvailable()
        testMP3IsFirstOutputFormat()
        testDefaultFormatFallsBackWhenMP3IsUnavailable()
        testDefaultFormatKeepsMP3WhenAvailable()
        testDefaultFormatKeepsAlwaysAvailableFormat()
        testMP3UnavailableExplanationIsUserFacing()
        testWaveformKeepsRollingWindow()
        testWaveformDetectsAmplitude()
        testRecordingTimelineSubtractsPausedGap()
        testSaveFailureReturnsErrorWhenStreamIsActive()
        testSaveFailureReturnsErrorWhenStreamIsInactive()
        testScreenCaptureTCCErrorMapsToScreenPermission()
        testMicrophonePermissionErrorIsActionable()
        print("CoreBehaviorTests passed")
    }
}

private func testFileNamingCreatesFirstDefaultName() throws {
    let folder = try TemporaryFolder()
    let service = FileNamingService(calendar: fixedCalendar, dateProvider: { fixedDate })

    let url = try service.nextAvailableRecordingURL(in: folder.url, format: .m4a)

    try expect(url.lastPathComponent == "260507 new recording 01.m4a", "default name should start at 01")
}

private func testFileNamingIncrementsExistingNames() throws {
    let folder = try TemporaryFolder()
    try Data().write(to: folder.url.appendingPathComponent("260507 new recording 01.m4a"))
    try Data().write(to: folder.url.appendingPathComponent("260507 new recording 02.m4a"))
    let service = FileNamingService(calendar: fixedCalendar, dateProvider: { fixedDate })

    let url = try service.nextAvailableRecordingURL(in: folder.url, format: .m4a)

    try expect(url.lastPathComponent == "260507 new recording 03.m4a", "default name should increment existing suffixes")
}

private func testInputGainUsesThreeTimesRangeAndDecibelLabels() {
    precondition(InputGain.minimumMultiplier == Float(1.0 / 3.0))
    precondition(InputGain.maximumMultiplier == 3)
    precondition(InputGain(multiplier: 9).multiplier == 3)
    precondition(InputGain(multiplier: 0.1).multiplier == Float(1.0 / 3.0))
    precondition(InputGain(multiplier: 1).decibelLabel == "0.0 dB")
    precondition(InputGain(multiplier: 3).decibelLabel == "+9.5 dB")
    precondition(InputGain(multiplier: Float(1.0 / 3.0)).decibelLabel == "-9.5 dB")
}

private func testRecordingInputModeLabels() {
    precondition(RecordingInputMode.allCases == [.computer, .computerAndMicrophone, .microphone])
    precondition(RecordingInputMode.computer.displayName == "Computer")
    precondition(RecordingInputMode.computerAndMicrophone.displayName == "Computer + Mic")
    precondition(RecordingInputMode.microphone.displayName == "Mic")
}

private func testMeterDetectsSilence() {
    var meter = AudioMeter()

    let reading = meter.process(samples: Array(repeating: 0, count: 256))

    precondition(reading.rms == 0)
    precondition(reading.peak == 0)
    precondition(reading.isSilent)
    precondition(reading.normalizedLevel == 0)
}

private func testMeterDetectsActiveSignal() {
    var meter = AudioMeter(silenceThreshold: 0.01)

    let reading = meter.process(samples: [0.25, -0.5, 0.75, -1.0])

    precondition(reading.rms > 0.65 && reading.rms < 0.7)
    precondition(reading.peak == 1.0)
    precondition(!reading.isSilent)
    precondition(reading.normalizedLevel == 1.0)
}

private func testMP3FormatIsAvailable() {
    precondition(OutputFormat.mp3.rawValue == "MP3")
    precondition(OutputFormat.mp3.fileExtension == "mp3")
}

private func testMP3IsFirstOutputFormat() {
    precondition(OutputFormat.allCases.first == .mp3)
}

private func testDefaultFormatFallsBackWhenMP3IsUnavailable() {
    precondition(OutputFormat.availableDefault(preferred: .mp3, isMP3Available: false) == .m4a)
}

private func testDefaultFormatKeepsMP3WhenAvailable() {
    precondition(OutputFormat.availableDefault(preferred: .mp3, isMP3Available: true) == .mp3)
}

private func testDefaultFormatKeepsAlwaysAvailableFormat() {
    precondition(OutputFormat.availableDefault(preferred: .wav, isMP3Available: false) == .wav)
}

private func testMP3UnavailableExplanationIsUserFacing() {
    precondition(AudioFileConverter.mp3UnavailableExplanation.contains("LAME"))
    precondition(AudioFileConverter.mp3InstallCommand == "brew install lame")
}

private func testWaveformKeepsRollingWindow() {
    var analyzer = WaveformAnalyzer(maxPoints: 3, samplesPerPoint: 4)

    for _ in 0..<12 {
        analyzer.process(samples: [0, 0.25, -0.5, 1])
    }

    precondition(analyzer.points.count == 3)
    precondition(analyzer.points.allSatisfy { $0.minimum == -0.5 && $0.maximum == 1 })
}

private func testWaveformDetectsAmplitude() {
    var analyzer = WaveformAnalyzer(maxPoints: 10, samplesPerPoint: 4)

    analyzer.process(samples: [-0.75, -0.25, 0.4, 0.9])

    precondition(analyzer.points.first?.minimum == -0.75)
    precondition(analyzer.points.first?.maximum == 0.9)
}

private func testRecordingTimelineSubtractsPausedGap() {
    var timeline = RecordingTimeline()

    let firstOffset = timeline.offsetForAppendedSample(
        presentationTime: CMTime(value: 10, timescale: 1),
        duration: CMTime(value: 1, timescale: 1)
    )
    timeline.pause()
    timeline.resume()
    let resumedOffset = timeline.offsetForAppendedSample(
        presentationTime: CMTime(value: 20, timescale: 1),
        duration: CMTime(value: 1, timescale: 1)
    )

    precondition(firstOffset == .zero)
    precondition(resumedOffset == CMTime(value: 9, timescale: 1))
}

private func testSaveFailureReturnsErrorWhenStreamIsActive() {
    let state = AudioRecorder.stateAfterSaveFailure(
        message: "No system audio was captured before stopping.",
        hasActiveStream: true
    )

    precondition(state == .error("No system audio was captured before stopping."))
}

private func testSaveFailureReturnsErrorWhenStreamIsInactive() {
    let state = AudioRecorder.stateAfterSaveFailure(
        message: "The recording could not be finalized.",
        hasActiveStream: false
    )

    precondition(state == .error("The recording could not be finalized."))
}

private func testScreenCaptureTCCErrorMapsToScreenPermission() {
    let error = NSError(
        domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
        code: 0,
        userInfo: [
            NSLocalizedDescriptionKey: "The user declined TCCs for application, window, display capture"
        ]
    )

    let mapped = AudioRecorder.mapScreenCaptureError(error)

    precondition(mapped.errorDescription?.contains("Screen & System Audio Recording") == true)
}

private func testMicrophonePermissionErrorIsActionable() {
    let message = RecorderError.microphonePermissionNeeded.errorDescription ?? ""

    precondition(message.contains("Microphone"))
    precondition(message.contains("Taurus Recorder"))
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TestFailure(message)
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private let fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
    return calendar
}()

private let fixedDate = DateComponents(
    calendar: fixedCalendar,
    timeZone: fixedCalendar.timeZone,
    year: 2026,
    month: 5,
    day: 7,
    hour: 9
).date!

private struct TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
