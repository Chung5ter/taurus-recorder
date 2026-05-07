import AVFoundation

public enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case mp3 = "MP3"
    case m4a = "M4A"
    case wav = "WAV"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .m4a:
            "m4a"
        case .mp3:
            "mp3"
        case .wav:
            "wav"
        }
    }

    public var isExportAvailable: Bool {
        switch self {
        case .m4a, .wav:
            true
        case .mp3:
            AudioFileConverter.isMP3ExportAvailable
        }
    }

    public static func availableDefault(
        preferred: OutputFormat?,
        isMP3Available: Bool = AudioFileConverter.isMP3ExportAvailable
    ) -> OutputFormat {
        switch preferred {
        case .mp3:
            isMP3Available ? .mp3 : .m4a
        case .m4a:
            .m4a
        case .wav:
            .wav
        case nil:
            isMP3Available ? .mp3 : .m4a
        }
    }

    var avFileType: AVFileType {
        switch self {
        case .m4a:
            .m4a
        case .mp3:
            .mp3
        case .wav:
            .wav
        }
    }

    func audioSettings(sampleRate: Double, channelCount: Int) -> [String: Any] {
        switch self {
        case .m4a:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: 192_000
            ]
        case .mp3:
            [
                AVFormatIDKey: kAudioFormatMPEGLayer3,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: 192_000
            ]
        case .wav:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }
}
