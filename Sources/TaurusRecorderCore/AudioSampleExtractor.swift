import AVFoundation
import CoreMedia
import Foundation

public enum AudioSampleExtractor {
    public static func monoFloatSamples(from sampleBuffer: CMSampleBuffer) throws -> [Float] {
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

        return try rawBufferList.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            return try decode(buffers: buffers, streamDescription: streamDescription)
        }
    }

    private static func decode(
        buffers: UnsafeMutableAudioBufferListPointer,
        streamDescription: AudioStreamBasicDescription
    ) throws -> [Float] {
        let formatFlags = streamDescription.mFormatFlags
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        let channelsPerFrame = max(Int(streamDescription.mChannelsPerFrame), 1)
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        if isFloat && bitsPerChannel == 32 {
            return decodeFloat32(buffers: buffers, channelsPerFrame: channelsPerFrame, isNonInterleaved: isNonInterleaved)
        }

        if !isFloat && bitsPerChannel == 16 {
            return decodeInt16(buffers: buffers, channelsPerFrame: channelsPerFrame, isNonInterleaved: isNonInterleaved)
        }

        throw RecorderError.unsupportedAudioBuffer
    }

    private static func decodeFloat32(
        buffers: UnsafeMutableAudioBufferListPointer,
        channelsPerFrame: Int,
        isNonInterleaved: Bool
    ) -> [Float] {
        if isNonInterleaved {
            let frameCount = buffers.map { Int($0.mDataByteSize) / MemoryLayout<Float>.size }.min() ?? 0
            guard frameCount > 0 else { return [] }
            var samples = Array(repeating: Float.zero, count: frameCount)

            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let values = data.assumingMemoryBound(to: Float.self)
                for index in 0..<frameCount {
                    samples[index] += values[index]
                }
            }

            let divisor = Float(max(buffers.count, 1))
            return samples.map { $0 / divisor }
        }

        guard let buffer = buffers.first, let data = buffer.mData else { return [] }
        let values = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let frameCount = sampleCount / channelsPerFrame
        var samples = Array(repeating: Float.zero, count: frameCount)

        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channelsPerFrame {
                sum += values[frame * channelsPerFrame + channel]
            }
            samples[frame] = sum / Float(channelsPerFrame)
        }

        return samples
    }

    private static func decodeInt16(
        buffers: UnsafeMutableAudioBufferListPointer,
        channelsPerFrame: Int,
        isNonInterleaved: Bool
    ) -> [Float] {
        let scale = Float(Int16.max)

        if isNonInterleaved {
            let frameCount = buffers.map { Int($0.mDataByteSize) / MemoryLayout<Int16>.size }.min() ?? 0
            guard frameCount > 0 else { return [] }
            var samples = Array(repeating: Float.zero, count: frameCount)

            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let values = data.assumingMemoryBound(to: Int16.self)
                for index in 0..<frameCount {
                    samples[index] += Float(values[index]) / scale
                }
            }

            let divisor = Float(max(buffers.count, 1))
            return samples.map { $0 / divisor }
        }

        guard let buffer = buffers.first, let data = buffer.mData else { return [] }
        let values = data.assumingMemoryBound(to: Int16.self)
        let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
        let frameCount = sampleCount / channelsPerFrame
        var samples = Array(repeating: Float.zero, count: frameCount)

        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channelsPerFrame {
                sum += Float(values[frame * channelsPerFrame + channel]) / scale
            }
            samples[frame] = sum / Float(channelsPerFrame)
        }

        return samples
    }
}
