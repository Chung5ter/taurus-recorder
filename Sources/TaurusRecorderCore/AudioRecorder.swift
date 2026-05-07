import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

public final class AudioRecorder: NSObject, @unchecked Sendable {
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
    private var stream: SCStream?
    private var writer: AudioFileWriter?
    private var meter = AudioMeter()
    private var waveform = WaveformAnalyzer()
    private var recordingTimeline = RecordingTimeline()
    private var captureSettings = AudioCaptureSettings()
    private var activeInputMode: RecordingInputMode?
    private var isPaused = false
    private var isStartingRecording = false
    private var monitoringStartTask: Task<Void, any Error>?

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
        var streamToRestart: SCStream?
        runtimeLock.withLock {
            self.captureSettings = requestedSettings
            if let stream,
               writer == nil,
               activeInputMode != requestedSettings.inputMode {
                self.stream = nil
                activeInputMode = nil
                streamToRestart = stream
            }
        }

        if let streamToRestart {
            try? await stopCapture(streamToRestart)
        }

        var taskToAwait: Task<Void, any Error>?
        var isAlreadyMonitoring = false
        var shouldNotifyMonitoring = false

        runtimeLock.withLock {
            if self.stream != nil {
                taskToAwait = nil
                isAlreadyMonitoring = true
                if self.currentState == .idle {
                    self.currentState = .monitoring
                    shouldNotifyMonitoring = true
                }
            } else if let monitoringStartTask = self.monitoringStartTask {
                taskToAwait = monitoringStartTask
            } else {
                let monitoringStartTask = Task { try await self.startAndStoreStream() }
                self.monitoringStartTask = monitoringStartTask
                taskToAwait = monitoringStartTask
            }
        }

        if shouldNotifyMonitoring {
            onStateChange?(.monitoring)
        }
        guard !isAlreadyMonitoring, let taskToAwait else {
            return
        }

        do {
            try await taskToAwait.value
        } catch {
            runtimeLock.withLock {
                self.monitoringStartTask = nil
            }
            throw error
        }

        let stateToNotify: RecordingState? = runtimeLock.withLock {
            self.monitoringStartTask = nil

            guard self.currentState == .idle else {
                return nil
            }

            self.currentState = .monitoring
            return .monitoring
        }
        if let stateToNotify {
            onStateChange?(stateToNotify)
        }
    }

    private func startAndStoreStream() async throws {
        let settings = runtimeLock.withLock { captureSettings }
        if settings.inputMode.capturesMicrophone, #unavailable(macOS 15.0) {
            throw RecorderError.microphoneCaptureUnsupported
        }
        if settings.inputMode.capturesMicrophone {
            try await Self.ensureMicrophonePermission()
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw Self.mapScreenCaptureError(error)
        }
        let displays = content.displays
        guard let display = displays.first else {
            throw RecorderError.noDisplayAvailable
        }

        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        let excludedApplications = content.applications.filter {
            $0.bundleIdentifier == currentBundleIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = settings.inputMode.capturesComputerAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.showsCursor = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        if settings.inputMode.capturesMicrophone {
            if #available(macOS 15.0, *) {
                configuration.captureMicrophone = true
            }
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        do {
            if settings.inputMode.capturesComputerAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
            }
            if settings.inputMode.capturesMicrophone {
                if #available(macOS 15.0, *) {
                    try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: captureQueue)
                }
            }
        } catch {
            throw RecorderError.streamOutputRegistrationFailed(error.localizedDescription)
        }

        try await startCapture(stream)
        runtimeLock.withLock {
            if self.stream == nil {
                self.stream = stream
                self.activeInputMode = settings.inputMode
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

        let needsMonitoring = try runtimeLock.withLock {
            guard !isStartingRecording,
                  writer == nil,
                  currentState == .idle || currentState == .monitoring else {
                throw RecorderError.writerFailed("Recording is already starting or in progress.")
            }
            isStartingRecording = true
            return stream == nil || activeInputMode != requestedSettings.inputMode
        }

        do {
            if needsMonitoring {
                try await startMonitoring(captureSettings: requestedSettings)
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
                expectedSources: requestedSettings.inputMode.capturedAudioSources
            )
            waveform.reset()
            recordingTimeline.reset()
            isPaused = false
            isStartingRecording = false
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
        let writerToFinish = runtimeLock.withLock {
            let writerToFinish = writer
            writer = nil
            isPaused = false
            recordingTimeline.reset()
            return writerToFinish
        }

        guard let writerToFinish else {
            transition(to: runtimeLock.withLock { stream == nil ? .idle : .monitoring })
            return
        }

        transition(to: .saving)

        do {
            let url = try await writerToFinish.finish()
            transition(to: runtimeLock.withLock { stream == nil ? .idle : .monitoring })
            onFinishedSaving?(url)
        } catch {
            let stateAfterFailure = runtimeLock.withLock {
                Self.stateAfterSaveFailure(
                    message: error.localizedDescription,
                    hasActiveStream: stream != nil
                )
            }
            transition(to: stateAfterFailure)
            onError?(error.localizedDescription)
        }
    }

    public func cancelRecording() {
        let result = runtimeLock.withLock {
            let writerToCancel = writer
            writer = nil
            isPaused = false
            isStartingRecording = false
            waveform.reset()
            recordingTimeline.reset()
            return (writerToCancel, waveform.points, stream == nil ? RecordingState.idle : .monitoring)
        }
        result.0?.cancel()
        onWaveform?(result.1)
        transition(to: result.2)
    }

    public func stopMonitoring() async {
        let result = runtimeLock.withLock {
            let writerToCancel = writer
            writer = nil
            isPaused = false
            isStartingRecording = false
            recordingTimeline.reset()
            return (writerToCancel, stream)
        }
        result.0?.cancel()

        guard let streamToStop = result.1 else {
            transition(to: .idle)
            return
        }

        do {
            try await stopCapture(streamToStop)
        } catch {
            onError?(error.localizedDescription)
        }

        runtimeLock.withLock {
            if self.stream === streamToStop {
                self.stream = nil
                self.activeInputMode = nil
            }
        }
        transition(to: .idle)
    }

    private func handle(sampleBuffer: CMSampleBuffer, source: CapturedAudioSource) {
        do {
            let gainedBuffer = try AudioSampleBufferGain.applying(
                runtimeLock.withLock { captureSettings.inputGain },
                to: sampleBuffer
            )
            let samples = try AudioSampleExtractor.monoFloatSamples(from: gainedBuffer)
            let result = runtimeLock.withLock {
                let reading = meter.process(samples: samples)
                var points: [WaveformPoint]?

                if currentState == .recording {
                    waveform.process(samples: samples)
                    points = waveform.points
                } else if currentState == .paused {
                    waveform.process(samples: Array(repeating: 0, count: samples.count))
                    points = waveform.points
                }

                let writerToAppend = currentState == .recording && !isPaused ? writer : nil
                let timestampOffset = writerToAppend == nil ? CMTime.zero : recordingTimeline.offsetForAppendedSample(
                    presentationTime: CMSampleBufferGetPresentationTimeStamp(gainedBuffer),
                    duration: CMSampleBufferGetDuration(gainedBuffer)
                )
                return (reading, points, writerToAppend, timestampOffset)
            }
            let reading = result.0
            onMeterReading?(reading)
            if let points = result.1 {
                onWaveform?(points)
            }

            try result.2?.append(gainedBuffer, source: source, subtracting: result.3)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func transition(to newState: RecordingState) {
        runtimeLock.withLock {
            currentState = newState
        }
        onStateChange?(newState)
    }

    private func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                return
            }
            throw RecorderError.microphonePermissionNeeded
        case .denied, .restricted:
            throw RecorderError.microphonePermissionNeeded
        @unknown default:
            throw RecorderError.microphonePermissionNeeded
        }
    }

    package static func mapScreenCaptureError(_ error: any Error) -> RecorderError {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
           nsError.code == -3801 || nsError.code == -3803 {
            return .screenRecordingPermissionNeeded
        }
        let message = nsError.localizedDescription.lowercased()
        if message.contains("tcc") || message.contains("declined") {
            return .screenRecordingPermissionNeeded
        }
        return .captureSetupFailed(error.localizedDescription)
    }

    package static func stateAfterSaveFailure(message: String, hasActiveStream: Bool) -> RecordingState {
        hasActiveStream ? .monitoring : .error(message)
    }
}

extension AudioRecorder: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else {
            return
        }
        if type == .audio {
            handle(sampleBuffer: sampleBuffer, source: .computer)
            return
        }
        if #available(macOS 15.0, *), type == .microphone {
            handle(sampleBuffer: sampleBuffer, source: .microphone)
            return
        }
    }
}

extension AudioRecorder: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let result: (AudioFileWriter?, Bool) = runtimeLock.withLock {
            guard self.stream === stream else {
                return (nil, false)
            }
            let writerToCancel = writer
            self.stream = nil
            activeInputMode = nil
            writer = nil
            isPaused = false
            isStartingRecording = false
            recordingTimeline.reset()
            monitoringStartTask = nil
            return (writerToCancel, true)
        }
        guard result.1 else {
            return
        }
        result.0?.cancel()
        transition(to: .error(error.localizedDescription))
        onError?(error.localizedDescription)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
