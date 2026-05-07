import AVFoundation
import CoreMedia
import Foundation

public enum AudioSampleBufferGain {
    public static func applying(_ gain: InputGain, to sampleBuffer: CMSampleBuffer) throws -> CMSampleBuffer {
        guard abs(gain.multiplier - 1) > 0.0001 else {
            return sampleBuffer
        }

        var copiedBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopy(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleBufferOut: &copiedBuffer
        )
        guard copyStatus == noErr, let copiedBuffer else {
            throw RecorderError.unsupportedAudioBuffer
        }

        try scaleAudioData(in: copiedBuffer, multiplier: gain.multiplier)
        return copiedBuffer
    }

    private static func scaleAudioData(in sampleBuffer: CMSampleBuffer, multiplier: Float) throws {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            throw RecorderError.unsupportedAudioBuffer
        }

        var requiredSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr, requiredSize > 0 else {
            throw RecorderError.unsupportedAudioBuffer
        }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        var blockBuffer: CMBlockBuffer?
        status = rawBufferList.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { audioBufferList in
            CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                bufferListSizeNeededOut: nil,
                bufferListOut: audioBufferList,
                bufferListSize: requiredSize,
                blockBufferAllocator: nil,
                blockBufferMemoryAllocator: nil,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &blockBuffer
            )
        }
        guard status == noErr else {
            throw RecorderError.unsupportedAudioBuffer
        }

        try rawBufferList.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            try scale(buffers: buffers, streamDescription: streamDescription, multiplier: multiplier)
        }
    }

    private static func scale(
        buffers: UnsafeMutableAudioBufferListPointer,
        streamDescription: AudioStreamBasicDescription,
        multiplier: Float
    ) throws {
        let formatFlags = streamDescription.mFormatFlags
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0

        if isFloat && bitsPerChannel == 32 {
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let values = data.assumingMemoryBound(to: Float.self)
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                for index in 0..<sampleCount {
                    values[index] = min(max(values[index] * multiplier, -1), 1)
                }
            }
            return
        }

        if !isFloat && bitsPerChannel == 16 {
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let values = data.assumingMemoryBound(to: Int16.self)
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                for index in 0..<sampleCount {
                    let scaled = Float(values[index]) * multiplier
                    values[index] = Int16(min(max(scaled, Float(Int16.min)), Float(Int16.max)))
                }
            }
            return
        }

        throw RecorderError.unsupportedAudioBuffer
    }
}
