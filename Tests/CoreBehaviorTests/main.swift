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
        testRecordingInputModeSelectableCasesExcludeCombinedMode()
        testAudioCaptureTargetDescribesAllAudioAndSpecificApps()
        testMeterDetectsSilence()
        testMeterDetectsActiveSignal()
        testMeterKeepsActivityThroughBriefQuietGap()
        testMeterReturnsToSilenceAfterSustainedQuiet()
        testMP3FormatIsAvailable()
        testMP3IsFirstOutputFormat()
        testDefaultFormatFallsBackWhenMP3IsUnavailable()
        testDefaultFormatKeepsMP3WhenAvailable()
        testDefaultFormatKeepsAlwaysAvailableFormat()
        testMP3UnavailableExplanationIsUserFacing()
        testWaveformKeepsRollingWindow()
        testWaveformDetectsAmplitude()
        testWaveformKeepsLatestDistinctChunksAfterManySamples()
        testRecordingTimelineSubtractsPausedGap()
        testVisualUpdateThrottleLimitsHighFrequencyAudioCallbacks()
        testRecorderPublishesVisualsNearThirtyFramesPerSecond()
        testVisualUpdateThrottleCanResetForNewRecording()
        testPlaybackTimelineClampsSkipTimes()
        testPlaybackTimelineCalculatesProgress()
        testPlaybackTimelineCalculatesTimeFromProgress()
        testMonitoringStateIsUserFacing()
        testSaveFailureReturnsErrorWhenStreamIsInactive()
        testSystemAudioPermissionMessageNamesAudioOnlyScope()
        print("CoreBehaviorTests passed")
    }
}

private func testFileNamingCreatesFirstDefaultName() throws {
    let folder = try TemporaryFolder()
    let service = FileNamingService(calendar: fixedCalendar, dateProvider: { fixedDate })

    let url = try service.nextAvailableRecordingURL(in: folder.url, format: .m4a)

    try expect(url.lastPathComponent == "260507 New Recording 01.m4a", "default name should start at 01")
}

private func testFileNamingIncrementsExistingNames() throws {
    let folder = try TemporaryFolder()
    try Data().write(to: folder.url.appendingPathComponent("260507 New Recording 01.m4a"))
    try Data().write(to: folder.url.appendingPathComponent("260507 New Recording 02.m4a"))
    let service = FileNamingService(calendar: fixedCalendar, dateProvider: { fixedDate })

    let url = try service.nextAvailableRecordingURL(in: folder.url, format: .m4a)

    try expect(url.lastPathComponent == "260507 New Recording 03.m4a", "default name should increment existing suffixes")
}

private func testInputGainUsesThreeTimesRangeAndDecibelLabels() {
    precondition(InputGain.notchedMultipliers == [Float(1.0 / 3.0), 0.5, 0.75, 1, 1.5, 2, 3])
    precondition(InputGain.minimumMultiplier == Float(1.0 / 3.0))
    precondition(InputGain.maximumMultiplier == 3)
    precondition(InputGain(multiplier: 9).multiplier == 3)
    precondition(InputGain(multiplier: 0.1).multiplier == Float(1.0 / 3.0))
    precondition(InputGain(multiplier: 1.2).multiplier == 1)
    precondition(InputGain(multiplier: 1.7).multiplier == 1.5)
    precondition(InputGain(notchIndex: 3).multiplier == 1)
    precondition(InputGain(notchIndex: 99).multiplier == 3)
    precondition(InputGain(multiplier: 1).decibelLabel == "0.0 dB")
    precondition(InputGain(multiplier: 3).decibelLabel == "+9.5 dB")
    precondition(InputGain(multiplier: Float(1.0 / 3.0)).decibelLabel == "-9.5 dB")
}

private func testRecordingInputModeLabels() {
    precondition(RecordingInputMode.allCases == [.computer])
    precondition(RecordingInputMode.computer.displayName == "Computer")
}

private func testRecordingInputModeSelectableCasesExcludeCombinedMode() {
    precondition(RecordingInputMode.selectableCases == [.computer])
    precondition(RecordingInputMode.computer.isSelectable)
    precondition(RecordingInputMode.computer.capturesComputerAudio)
}

private func testAudioCaptureTargetDescribesAllAudioAndSpecificApps() {
    precondition(AudioCaptureTarget.allComputerAudio.displayName == "All Computer Audio")
    precondition(AudioCaptureSettings().target == .allComputerAudio)

    let zoom = AudioCaptureTarget.application(bundleIdentifier: "us.zoom.xos", displayName: "zoom.us")
    precondition(zoom.displayName == "zoom.us")
    precondition(zoom.bundleIdentifier == "us.zoom.xos")
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

private func testMeterKeepsActivityThroughBriefQuietGap() {
    var meter = AudioMeter(silenceThreshold: 0.01)

    _ = meter.process(samples: [0.25, -0.5, 0.75, -1.0])
    let reading = meter.process(samples: Array(repeating: 0, count: 256))

    precondition(!reading.isSilent)
}

private func testMeterReturnsToSilenceAfterSustainedQuiet() {
    var meter = AudioMeter(silenceThreshold: 0.01, silenceReleaseCount: 2)

    _ = meter.process(samples: [0.25, -0.5, 0.75, -1.0])
    _ = meter.process(samples: Array(repeating: 0, count: 256))
    let reading = meter.process(samples: Array(repeating: 0, count: 256))

    precondition(reading.isSilent)
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

private func testWaveformKeepsLatestDistinctChunksAfterManySamples() {
    var analyzer = WaveformAnalyzer(maxPoints: 4, samplesPerPoint: 2)

    for step in 0..<10_000 {
        let value = Float(step) / 10_000
        analyzer.process(samples: [-value, value])
    }

    precondition(analyzer.points.count == 4)
    precondition(analyzer.points.first?.minimum == -0.9996)
    precondition(analyzer.points.last?.maximum == 0.9999)
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

private func testVisualUpdateThrottleLimitsHighFrequencyAudioCallbacks() {
    var throttle = VisualUpdateThrottle(interval: 0.1)
    var publishCount = 0

    for step in 0..<100 {
        if throttle.shouldPublish(at: Double(step) * 0.01) {
            publishCount += 1
        }
    }

    precondition(publishCount == 10)
}

private func testRecorderPublishesVisualsNearThirtyFramesPerSecond() {
    let expectedInterval = 1.0 / 30.0

    precondition(abs(AudioRecorder.visualUpdateInterval - expectedInterval) < 0.000_001)
}

private func testVisualUpdateThrottleCanResetForNewRecording() {
    var throttle = VisualUpdateThrottle(interval: 10)

    precondition(throttle.shouldPublish(at: 100))
    precondition(!throttle.shouldPublish(at: 101))
    throttle.reset()
    precondition(throttle.shouldPublish(at: 101))
}

private func testPlaybackTimelineClampsSkipTimes() {
    let timeline = PlaybackTimeline(duration: 30)

    precondition(timeline.time(afterSkipping: -10, from: 4) == 0)
    precondition(timeline.time(afterSkipping: 10, from: 25) == 30)
    precondition(timeline.time(afterSkipping: 10, from: 8) == 18)
}

private func testPlaybackTimelineCalculatesProgress() {
    precondition(PlaybackTimeline(duration: 40).progress(at: 10) == 0.25)
    precondition(PlaybackTimeline(duration: 0).progress(at: 10) == 0)
}

private func testPlaybackTimelineCalculatesTimeFromProgress() {
    let timeline = PlaybackTimeline(duration: 40)

    precondition(timeline.time(atProgress: 0.25) == 10)
    precondition(timeline.time(atProgress: -1) == 0)
    precondition(timeline.time(atProgress: 2) == 40)
    precondition(PlaybackTimeline(duration: 0).time(atProgress: 0.5) == 0)
}

private func testMonitoringStateIsUserFacing() {
    precondition(RecordingState.monitoring.title == "Idle")
}

private func testSaveFailureReturnsErrorWhenStreamIsInactive() {
    let state = AudioRecorder.stateAfterSaveFailure(message: "The recording could not be finalized.")

    precondition(state == .error("The recording could not be finalized."))
}

private func testSystemAudioPermissionMessageNamesAudioOnlyScope() {
    let error = RecorderError.systemAudioRecordingPermissionNeeded

    precondition(error.errorDescription?.contains("System Audio Recording Only") == true)
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
