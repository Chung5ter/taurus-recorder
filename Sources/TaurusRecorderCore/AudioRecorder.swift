import CoreMedia
import Foundation

public final class AudioRecorder: NSObject, @unchecked Sendable {
    package static let visualUpdateInterval: TimeInterval = 1.0 / 30.0

    public var onMeterReading: (@Sendable (MeterReading) -> Void)?
    public var onWaveform: (@Sendable ([WaveformPoint]) -> Void)?
    public var onStateChange: (@Sendable (RecordingState) -> Void)?
    public var onError: (@Sendable (String) -> Void)?
    public var onFinishedSaving: (@Sendable (URL) -> Void)?

    public var state: RecordingState {
        runtimeLock.withLock { currentState }
    }

    private let permissionHelper: ScreenCapturePermissionHelper
    private let captureQueue = DispatchQueue(label: "simple-audio-recorder.capture")
    private let runtimeLock = NSLock()
    private var currentState: RecordingState = .idle
    private var capture: CoreAudioTapCapture?
    private var writer: AudioFileWriter?
    private var meter = AudioMeter()
    private var waveform = WaveformAnalyzer()
    private var recordingTimeline = RecordingTimeline()
    private var captureSettings = AudioCaptureSettings()
    private var activeTarget: AudioCaptureTarget?
    private var isPaused = false
    private var isStartingRecording = false
    private var visualUpdateThrottle = VisualUpdateThrottle(interval: AudioRecorder.visualUpdateInterval)

    public init(permissionHelper: ScreenCapturePermissionHelper = ScreenCapturePermissionHelper()) {
        self.permissionHelper = permissionHelper
        super.init()
    }

    public func updateInputGain(_ inputGain: InputGain) {
        runtimeLock.withLock {
            captureSettings.inputGain = inputGain
        }
    }

    public func startMonitoring(captureSettings requestedSettings: AudioCaptureSettings = AudioCaptureSettings()) async throws {
        runtimeLock.withLock {
            self.captureSettings = requestedSettings
        }

        let captureToReplace = runtimeLock.withLock {
            guard let capture, activeTarget != requestedSettings.target else {
                return nil as CoreAudioTapCapture?
            }
            self.capture = nil
            activeTarget = nil
            return capture
        }
        if let captureToReplace {
            captureToReplace.stop()
        }

        let needsCapture = runtimeLock.withLock {
            guard currentState != .recording,
                  currentState != .paused,
                  currentState != .saving,
                  !isStartingRecording else {
                return false
            }
            isStartingRecording = capture == nil
            return capture == nil
        }

        do {
            if needsCapture {
                try startAndStoreCapture()
            }
        } catch {
            runtimeLock.withLock {
                isStartingRecording = false
            }
            throw error
        }

        let didStartMonitoring = runtimeLock.withLock {
            isStartingRecording = false
            return capture != nil && currentState != .monitoring
        }
        if didStartMonitoring {
            transition(to: .monitoring)
        }
    }

    private func startAndStoreCapture() throws {
        let settings = runtimeLock.withLock { captureSettings }
        let capture = CoreAudioTapCapture(queue: captureQueue) { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer, source: .computer)
        }
        try capture.start(target: settings.target)
        runtimeLock.withLock {
            if self.capture == nil {
                self.capture = capture
                self.activeTarget = settings.target
            }
        }
    }

    public func startRecording(
        outputURL: URL,
        format: OutputFormat,
        captureSettings requestedSettings: AudioCaptureSettings = AudioCaptureSettings()
    ) async throws {
        runtimeLock.withLock {
            self.captureSettings = requestedSettings
        }

        let captureToReplace = runtimeLock.withLock {
            guard let capture, activeTarget != requestedSettings.target else {
                return nil as CoreAudioTapCapture?
            }
            self.capture = nil
            activeTarget = nil
            return capture
        }
        if let captureToReplace {
            captureToReplace.stop()
        }

        let needsCapture = try runtimeLock.withLock {
            let canStart: Bool
            switch currentState {
            case .idle, .monitoring, .error:
                canStart = true
            case .recording, .paused, .saving:
                canStart = false
            }
            guard !isStartingRecording,
                  writer == nil,
                  canStart else {
                throw RecorderError.writerFailed("Recording is already starting or in progress.")
            }
            isStartingRecording = true
            return capture == nil
        }

        do {
            if needsCapture {
                try startAndStoreCapture()
            }
        } catch {
            runtimeLock.withLock {
                isStartingRecording = false
            }
            throw error
        }

        runtimeLock.withLock {
            writer = AudioFileWriter(
                outputURL: outputURL,
                outputFormat: format,
                expectedSources: [.computer]
            )
            waveform.reset()
            recordingTimeline.reset()
            isPaused = false
            isStartingRecording = false
            visualUpdateThrottle.reset()
        }
        transition(to: .recording)
    }

    public func pauseRecording() {
        let didPause = runtimeLock.withLock {
            guard currentState == .recording else { return false }
            isPaused = true
            recordingTimeline.pause()
            return true
        }
        if didPause {
            transition(to: .paused)
        }
    }

    public func resumeRecording() {
        let didResume = runtimeLock.withLock {
            guard currentState == .paused else { return false }
            isPaused = false
            recordingTimeline.resume()
            return true
        }
        if didResume {
            transition(to: .recording)
        }
    }

    public func stopRecording() async {
        let stopContext = runtimeLock.withLock {
            let writerToFinish = writer
            writer = nil
            isPaused = false
            recordingTimeline.reset()
            visualUpdateThrottle.reset()
            let captureToStop = capture
            capture = nil
            activeTarget = nil
            return (writerToFinish, captureToStop)
        }

        guard let writerToFinish = stopContext.0 else {
            stopContext.1?.stop()
            transition(to: .idle)
            return
        }

        stopContext.1?.stop()
        transition(to: .saving)

        do {
            let url = try await writerToFinish.finish()
            transition(to: .idle)
            onFinishedSaving?(url)
        } catch {
            let stateAfterFailure = Self.stateAfterSaveFailure(message: error.localizedDescription)
            transition(to: stateAfterFailure)
            onError?(error.localizedDescription)
        }
    }

    public func cancelRecording() async {
        let result = runtimeLock.withLock {
            let writerToCancel = writer
            writer = nil
            isPaused = false
            isStartingRecording = false
            waveform.reset()
            recordingTimeline.reset()
            visualUpdateThrottle.reset()
            let captureToStop = capture
            capture = nil
            activeTarget = nil
            return (writerToCancel, waveform.points, captureToStop)
        }
        result.0?.cancel()
        result.2?.stop()
        onWaveform?(result.1)
        transition(to: .idle)
    }

    public func stopCaptureStream() async {
        let result = runtimeLock.withLock {
            let writerToCancel = writer
            writer = nil
            isPaused = false
            isStartingRecording = false
            recordingTimeline.reset()
            visualUpdateThrottle.reset()
            let captureToStop = capture
            capture = nil
            activeTarget = nil
            return (writerToCancel, captureToStop)
        }
        result.0?.cancel()

        guard let captureToStop = result.1 else {
            transition(to: .idle)
            return
        }

        captureToStop.stop()
        transition(to: .idle)
    }

    private func handle(sampleBuffer: CMSampleBuffer, source: CapturedAudioSource) {
        do {
            let gainedBuffer = try AudioSampleBufferGain.applying(
                runtimeLock.withLock { captureSettings.inputGain },
                to: sampleBuffer
            )
            let now = ProcessInfo.processInfo.systemUptime
            let result = runtimeLock.withLock {
                let state = currentState
                let writerToAppend = currentState == .recording && !isPaused ? writer : nil
                let timestampOffset = writerToAppend == nil ? CMTime.zero : recordingTimeline.offsetForAppendedSample(
                    presentationTime: CMSampleBufferGetPresentationTimeStamp(gainedBuffer),
                    duration: CMSampleBufferGetDuration(gainedBuffer)
                )
                let shouldPublishVisuals = visualUpdateThrottle.shouldPublish(at: now)
                return (shouldPublishVisuals, state, writerToAppend, timestampOffset)
            }

            if result.0 {
                do {
                    let samples = try AudioSampleExtractor.monoFloatSamples(from: gainedBuffer)
                    let visuals = runtimeLock.withLock {
                        let reading = meter.process(samples: samples)
                        var points: [WaveformPoint]?

                        if result.1 == .recording {
                            waveform.process(samples: samples)
                            points = waveform.points
                        } else if result.1 == .paused {
                            waveform.process(samples: Array(repeating: 0, count: samples.count))
                            points = waveform.points
                        }
                        return (reading, points)
                    }
                    onMeterReading?(visuals.0)
                    if let points = visuals.1 {
                        onWaveform?(points)
                    }
                } catch {
                    onError?(error.localizedDescription)
                }
            }

            do {
                try result.2?.append(gainedBuffer, source: source, subtracting: result.3)
            } catch {
                failActiveRecording(with: error)
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func failActiveRecording(with error: any Error) {
        let message = error.localizedDescription
        let result: (AudioFileWriter?, CoreAudioTapCapture?, Bool) = runtimeLock.withLock {
            guard currentState == .recording || currentState == .paused else {
                return (nil, nil, false)
            }
            let writerToCancel = writer
            writer = nil
            isPaused = false
            isStartingRecording = false
            recordingTimeline.reset()
            visualUpdateThrottle.reset()
            let captureToStop = capture
            capture = nil
            activeTarget = nil
            return (writerToCancel, captureToStop, true)
        }

        guard result.2 else {
            return
        }

        result.0?.cancel()
        result.1?.stop()
        transition(to: .error(message))
        onError?(message)
    }

    private func transition(to newState: RecordingState) {
        runtimeLock.withLock {
            currentState = newState
        }
        onStateChange?(newState)
    }

    package static func stateAfterSaveFailure(message: String) -> RecordingState {
        .error(message)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
