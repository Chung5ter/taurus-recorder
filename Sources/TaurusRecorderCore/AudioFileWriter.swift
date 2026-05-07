import AVFoundation
import CoreMedia
import Foundation

public final class AudioFileWriter: @unchecked Sendable {
    public let outputURL: URL

    private let outputFormat: OutputFormat
    private let expectedSources: Set<CapturedAudioSource>
    private var writer: AVAssetWriter?
    private var inputs: [CapturedAudioSource: AVAssetWriterInput] = [:]
    private var pendingFirstBuffers: [CapturedAudioSource: CMSampleBuffer] = [:]
    private var didStartSession = false
    private let lock = NSLock()

    public init(outputURL: URL, outputFormat: OutputFormat) {
        self.outputURL = outputURL
        self.outputFormat = outputFormat
        self.expectedSources = [.computer]
    }

    init(outputURL: URL, outputFormat: OutputFormat, expectedSources: Set<CapturedAudioSource>) {
        self.outputURL = outputURL
        self.outputFormat = outputFormat
        self.expectedSources = expectedSources.isEmpty ? [.computer] : expectedSources
    }

    public func append(_ sampleBuffer: CMSampleBuffer, subtracting timestampOffset: CMTime = .zero) throws {
        try append(sampleBuffer, source: .computer, subtracting: timestampOffset)
    }

    func append(
        _ sampleBuffer: CMSampleBuffer,
        source: CapturedAudioSource,
        subtracting timestampOffset: CMTime = .zero
    ) throws {
        let sampleBuffer = try retimedSampleBuffer(sampleBuffer, subtracting: timestampOffset)

        lock.lock()
        defer { lock.unlock() }

        if writer == nil {
            pendingFirstBuffers[source] = sampleBuffer
            guard expectedSources.isSubset(of: Set(pendingFirstBuffers.keys)) else {
                return
            }

            try configureWriter(using: pendingFirstBuffers)
            let buffersToAppend = pendingFirstBuffers
                .sorted { lhs, rhs in
                    CMTimeCompare(
                        CMSampleBufferGetPresentationTimeStamp(lhs.value),
                        CMSampleBufferGetPresentationTimeStamp(rhs.value)
                    ) < 0
                }
            pendingFirstBuffers.removeAll()
            for (source, pendingBuffer) in buffersToAppend {
                try appendUnlocked(pendingBuffer, source: source)
            }
            return
        }

        try appendUnlocked(sampleBuffer, source: source)
    }

    private func appendUnlocked(_ sampleBuffer: CMSampleBuffer, source: CapturedAudioSource) throws {
        guard let writer, let input = inputs[source] else {
            throw RecorderError.writerNotReady
        }

        guard writer.status == .writing else {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "Writer is not accepting audio.")
        }

        if input.isReadyForMoreMediaData {
            let didAppend = input.append(sampleBuffer)
            if !didAppend {
                throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "Audio sample could not be appended.")
            }
        }
    }

    private func retimedSampleBuffer(_ sampleBuffer: CMSampleBuffer, subtracting timestampOffset: CMTime) throws -> CMSampleBuffer {
        guard timestampOffset.isValid, CMTimeCompare(timestampOffset, .zero) != 0 else {
            return sampleBuffer
        }

        var timingInfoCount = 0
        var status = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingInfoCount
        )
        guard status == noErr, timingInfoCount > 0 else {
            throw RecorderError.unsupportedAudioBuffer
        }

        var timingInfo = Array(
            repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
            count: timingInfoCount
        )
        status = timingInfo.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: timingInfoCount,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &timingInfoCount
            )
        }
        guard status == noErr else {
            throw RecorderError.unsupportedAudioBuffer
        }

        for index in timingInfo.indices {
            if timingInfo[index].presentationTimeStamp.isValid {
                timingInfo[index].presentationTimeStamp = timingInfo[index].presentationTimeStamp - timestampOffset
            }
            if timingInfo[index].decodeTimeStamp.isValid {
                timingInfo[index].decodeTimeStamp = timingInfo[index].decodeTimeStamp - timestampOffset
            }
        }

        var retimedBuffer: CMSampleBuffer?
        status = timingInfo.withUnsafeBufferPointer { buffer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: timingInfo.count,
                sampleTimingArray: buffer.baseAddress,
                sampleBufferOut: &retimedBuffer
            )
        }
        guard status == noErr, let retimedBuffer else {
            throw RecorderError.unsupportedAudioBuffer
        }

        return retimedBuffer
    }

    public func finish() async throws -> URL {
        let writerAndInputs: (AVAssetWriter, [AVAssetWriterInput])? = lock.withLock {
            guard let writer, !inputs.isEmpty else {
                return nil
            }
            let inputs = Array(inputs.values)
            inputs.forEach { $0.markAsFinished() }
            return (writer, inputs)
        }

        guard let (writer, _) = writerAndInputs else {
            throw RecorderError.writerFailed("No audio was captured before stopping.")
        }

        await writer.finishWriting()

        lock.withLock {
            self.writer = nil
            self.inputs = [:]
            self.pendingFirstBuffers = [:]
            self.didStartSession = false
        }

        if writer.status == .failed || writer.status == .cancelled {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "The recording could not be finalized.")
        }

        return outputURL
    }

    public func cancel() {
        lock.withLock {
            writer?.cancelWriting()
            writer = nil
            inputs = [:]
            pendingFirstBuffers = [:]
            didStartSession = false
        }
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func configureWriter(using firstBuffers: [CapturedAudioSource: CMSampleBuffer]) throws {
        guard outputFormat != .mp3 else {
            throw RecorderError.writerFailed("MP3 is finalized after recording. Record to a temporary M4A first.")
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: outputFormat.avFileType)

        for source in firstBuffers.keys.sorted() {
            guard let sampleBuffer = firstBuffers[source],
                  let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
                throw RecorderError.unsupportedAudioBuffer
            }

            let sampleRate = streamDescription.mSampleRate > 0 ? streamDescription.mSampleRate : 48_000
            let channelCount = max(Int(streamDescription.mChannelsPerFrame), 1)
            let outputSettings = outputFormat.audioSettings(sampleRate: sampleRate, channelCount: channelCount)
            guard writer.canApply(outputSettings: outputSettings, forMediaType: .audio) else {
                throw RecorderError.writerFailed("\(outputFormat.rawValue) output is not supported by AVAssetWriter on this Mac.")
            }
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: outputSettings,
                sourceFormatHint: formatDescription
            )
            input.expectsMediaDataInRealTime = true

            guard writer.canAdd(input) else {
                throw RecorderError.writerFailed("The audio input could not be added for \(outputFormat.rawValue) output.")
            }

            writer.add(input)
            inputs[source] = input
        }

        guard writer.startWriting() else {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "The audio writer could not start.")
        }

        let startTime = firstBuffers.values
            .map { CMSampleBufferGetPresentationTimeStamp($0) }
            .filter(\.isValid)
            .min { CMTimeCompare($0, $1) < 0 } ?? .zero
        writer.startSession(atSourceTime: startTime)

        self.writer = writer
        self.didStartSession = true
    }
}

enum CapturedAudioSource: Comparable, Sendable {
    case computer
    case microphone
}

extension RecordingInputMode {
    var capturedAudioSources: Set<CapturedAudioSource> {
        switch self {
        case .computer:
            [.computer]
        case .computerAndMicrophone:
            [.computer, .microphone]
        case .microphone:
            [.microphone]
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
