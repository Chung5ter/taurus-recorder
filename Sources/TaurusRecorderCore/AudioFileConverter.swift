import Foundation

public struct AudioFileConverter: Sendable {
    public init() {}

    public static let mp3InstallCommand = "brew install lame"

    public static let mp3UnavailableExplanation = "MP3 export is unavailable because Taurus Recorder needs the LAME encoder to create MP3 files."

    public static var isMP3ExportAvailable: Bool {
        findLAMEURL() != nil
    }

    public func convertToMP3(inputURL: URL, outputURL: URL) throws {
        let lameURL = try findLAME()
        let temporaryWAV = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaurusRecorder-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporaryWAV) }

        try run(
            executableURL: URL(fileURLWithPath: "/usr/bin/afconvert"),
            arguments: [
                "-f", "WAVE",
                "-d", "LEI16",
                inputURL.path,
                temporaryWAV.path
            ],
            failureMessage: "Could not prepare audio for MP3 conversion."
        )

        try run(
            executableURL: lameURL,
            arguments: [
                "-b", "192",
                temporaryWAV.path,
                outputURL.path
            ],
            failureMessage: "Could not encode MP3."
        )
    }

    private func findLAME() throws -> URL {
        if let url = Self.findLAMEURL() {
            return url
        }

        throw RecorderError.writerFailed("\(Self.mp3UnavailableExplanation) Choose M4A or WAV instead.")
    }

    private static func findLAMEURL() -> URL? {
        if let bundledURL = Bundle.main.url(forResource: "lame", withExtension: nil, subdirectory: "Encoders"),
           FileManager.default.isExecutableFile(atPath: bundledURL.path) {
            return bundledURL
        }

        let candidates = [
            "/opt/homebrew/bin/lame",
            "/usr/local/bin/lame",
            "/usr/bin/lame"
        ]

        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func run(
        executableURL: URL,
        arguments: [String],
        failureMessage: String
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        let errorCollector = ProcessOutputCollector()
        let errorHandle = errorPipe.fileHandleForReading
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            errorCollector.append(data)
        }

        do {
            try process.run()
        } catch {
            errorHandle.readabilityHandler = nil
            throw error
        }

        process.waitUntilExit()
        errorHandle.readabilityHandler = nil
        errorCollector.append(errorHandle.readDataToEndOfFile())

        guard process.terminationStatus == 0 else {
            let message = String(data: errorCollector.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RecorderError.writerFailed(message?.isEmpty == false ? message! : failureMessage)
        }
    }
}

private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collectedData = Data()

    var data: Data {
        lock.withLock { collectedData }
    }

    func append(_ data: Data) {
        lock.withLock {
            collectedData.append(data)
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
