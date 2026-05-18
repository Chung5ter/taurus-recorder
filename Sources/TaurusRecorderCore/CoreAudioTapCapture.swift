import AppKit
import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

final class CoreAudioTapCapture: @unchecked Sendable {
    typealias SampleHandler = @Sendable (CMSampleBuffer) -> Void

    private let queue: DispatchQueue
    private let sampleHandler: SampleHandler
    private let lock = NSLock()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var streamDescription = AudioStreamBasicDescription()
    private var formatDescription: CMAudioFormatDescription?
    private var nextFramePosition: Int64 = 0
    private var isRunning = false

    init(queue: DispatchQueue, sampleHandler: @escaping SampleHandler) {
        self.queue = queue
        self.sampleHandler = sampleHandler
    }

    func start(target: AudioCaptureTarget) throws {
        guard #available(macOS 14.2, *) else {
            throw RecorderError.captureSetupFailed("System Audio Recording Only requires macOS 14.2 or later.")
        }

        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else {
            return
        }

        do {
            let tapDescription = try makeTapDescription(for: target)
            var createdTapID = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateProcessTap(tapDescription, &createdTapID), "create system audio tap")
            tapID = createdTapID

            aggregateDeviceID = try createAggregateDevice(for: tapDescription)
            streamDescription = try getStreamDescription(for: aggregateDeviceID)
            formatDescription = try makeFormatDescription(streamDescription)

            var createdIOProcID: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProcID,
                aggregateDeviceID,
                queue
            ) { [weak self] _, inputData, _, _, _ in
                self?.handle(inputData: inputData)
            }
            try check(status, "create audio input callback")
            ioProcID = createdIOProcID

            try check(AudioDeviceStart(aggregateDeviceID, ioProcID), "start system audio capture")
            isRunning = true
        } catch {
            cleanupLocked()
            throw error
        }
    }

    func stop() {
        lock.lock()
        cleanupLocked()
        lock.unlock()
    }

    private func makeTapDescription(for target: AudioCaptureTarget) throws -> CATapDescription {
        let description: CATapDescription

        switch target {
        case .allComputerAudio:
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: currentProcessObjectIDs())
        case .application(let bundleIdentifier, let displayName):
            let processIDs = processObjectIDs(for: bundleIdentifier)
            guard !processIDs.isEmpty else {
                throw RecorderError.targetApplicationUnavailable(displayName)
            }
            description = CATapDescription(stereoMixdownOfProcesses: processIDs)
        }

        description.name = "Taurus Recorder System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        return description
    }

    private func createAggregateDevice(for tapDescription: CATapDescription) throws -> AudioObjectID {
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let tapUID = tapDescription.uuid.uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Taurus Recorder Capture",
            kAudioAggregateDeviceUIDKey: "com.local.TaurusRecorder.capture.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "create private capture device")
        return aggregateID
    }

    private func getStreamDescription(for deviceID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streamDescription),
            "read capture audio format"
        )
        return streamDescription
    }

    private func makeFormatDescription(_ streamDescription: AudioStreamBasicDescription) throws -> CMAudioFormatDescription {
        var streamDescription = streamDescription
        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        try check(status, "create capture format description")
        guard let formatDescription else {
            throw RecorderError.unsupportedAudioBuffer
        }
        return formatDescription
    }

    private func handle(inputData: UnsafePointer<AudioBufferList>?) {
        guard let inputData else {
            return
        }

        do {
            let sampleBuffer = try makeSampleBuffer(from: inputData)
            sampleHandler(sampleBuffer)
        } catch {
            // The callback has no error return path. Surface capture failures through silence; the
            // recorder will report writer/meter errors on the main processing path when possible.
        }
    }

    private func makeSampleBuffer(from inputData: UnsafePointer<AudioBufferList>) throws -> CMSampleBuffer {
        let snapshot = lock.withLock {
            (streamDescription, formatDescription, nextFramePosition)
        }
        guard let formatDescription = snapshot.1 else {
            throw RecorderError.unsupportedAudioBuffer
        }

        let sampleRate = snapshot.0.mSampleRate > 0 ? snapshot.0.mSampleRate : 48_000
        let frameCount = frameCount(in: inputData, streamDescription: snapshot.0)
        guard frameCount > 0 else {
            throw RecorderError.unsupportedAudioBuffer
        }

        let duration = CMTime(value: 1, timescale: CMTimeScale(sampleRate.rounded()))
        let presentationTime = CMTime(value: snapshot.2, timescale: CMTimeScale(sampleRate.rounded()))
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleSize = sampleSize(in: inputData, streamDescription: snapshot.0)
        var sampleBuffer: CMSampleBuffer?
        let sampleSizeEntryCount = sampleSize == nil ? 0 : 1

        let createStatus = withUnsafePointer(to: &timing) { timingPointer in
            withOptionalUnsafePointer(to: &sampleSize) { sampleSizePointer in
                CMSampleBufferCreate(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: nil,
                    dataReady: false,
                    makeDataReadyCallback: nil,
                    refcon: nil,
                    formatDescription: formatDescription,
                    sampleCount: frameCount,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: timingPointer,
                    sampleSizeEntryCount: sampleSizeEntryCount,
                    sampleSizeArray: sampleSizePointer,
                    sampleBufferOut: &sampleBuffer
                )
            }
        }
        try check(createStatus, "create audio sample buffer")
        guard let sampleBuffer else {
            throw RecorderError.unsupportedAudioBuffer
        }

        try check(
            CMSampleBufferSetDataBufferFromAudioBufferList(
                sampleBuffer,
                blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault,
                flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
                bufferList: inputData
            ),
            "copy audio input buffer"
        )

        lock.withLock {
            nextFramePosition += Int64(frameCount)
        }
        return sampleBuffer
    }

    private func frameCount(
        in audioBufferList: UnsafePointer<AudioBufferList>,
        streamDescription: AudioStreamBasicDescription
    ) -> CMItemCount {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let bytesPerFrame = max(Int(streamDescription.mBytesPerFrame), 1)
        let formatFlags = streamDescription.mFormatFlags
        let isNonInterleaved = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        if isNonInterleaved {
            return buffers.map { CMItemCount(Int($0.mDataByteSize) / bytesPerFrame) }.min() ?? 0
        }

        guard let buffer = buffers.first else {
            return 0
        }
        return CMItemCount(Int(buffer.mDataByteSize) / bytesPerFrame)
    }

    private func sampleSize(
        in audioBufferList: UnsafePointer<AudioBufferList>,
        streamDescription: AudioStreamBasicDescription
    ) -> Int? {
        let isNonInterleaved = (streamDescription.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        guard !isNonInterleaved else {
            return nil
        }
        let bytesPerFrame = Int(streamDescription.mBytesPerFrame)
        return bytesPerFrame > 0 ? bytesPerFrame : nil
    }

    private func currentProcessObjectIDs() -> [AudioObjectID] {
        let currentPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        guard let processID = processObjectID(for: currentPID) else {
            return []
        }
        return [processID]
    }

    private func processObjectIDs(for bundleIdentifier: String) -> [AudioObjectID] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .compactMap { application in
                processObjectID(for: application.processIdentifier)
            }
    }

    private func processObjectID(for pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &processObjectID
        )
        guard status == noErr, processObjectID != kAudioObjectUnknown else {
            return nil
        }
        return processObjectID
    }

    private func cleanupLocked() {
        if let ioProcID {
            _ = AudioDeviceStop(aggregateDeviceID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                _ = AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        formatDescription = nil
        streamDescription = AudioStreamBasicDescription()
        nextFramePosition = 0
        isRunning = false
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            if status == kAudioDevicePermissionsError {
                throw RecorderError.systemAudioRecordingPermissionNeeded
            }
            throw RecorderError.captureSetupFailed("\(operation) failed (\(status))")
        }
    }
}

private func withOptionalUnsafePointer<T, R>(
    to value: inout T?,
    _ body: (UnsafePointer<T>?) -> R
) -> R {
    guard let unwrapped = value else {
        return body(nil)
    }
    return withUnsafePointer(to: unwrapped) { pointer in
        body(pointer)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
