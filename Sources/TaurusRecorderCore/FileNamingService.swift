import Foundation

public struct FileNamingService {
    private let calendar: Calendar
    private let dateProvider: @Sendable () -> Date
    private let fileManager: FileManager

    public init(
        calendar: Calendar = .current,
        dateProvider: @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.calendar = calendar
        self.dateProvider = dateProvider
        self.fileManager = fileManager
    }

    public func nextAvailableRecordingURL(
        in folder: URL,
        format: OutputFormat,
        customBaseName: String? = nil
    ) throws -> URL {
        let baseName = sanitizedBaseName(customBaseName) ?? defaultBaseName(for: dateProvider())
        return try nextAvailableURL(in: folder, baseName: baseName, format: format, usesTightDefaultSuffix: customBaseName == nil)
    }

    public func nextAvailableURL(
        in folder: URL,
        baseName: String,
        format: OutputFormat
    ) throws -> URL {
        try nextAvailableURL(
            in: folder,
            baseName: sanitizedBaseName(baseName) ?? defaultBaseName(for: dateProvider()),
            format: format,
            usesTightDefaultSuffix: false
        )
    }

    private func nextAvailableURL(
        in folder: URL,
        baseName: String,
        format: OutputFormat,
        usesTightDefaultSuffix: Bool
    ) throws -> URL {
        var index = 1

        while true {
            let suffix: String
            if usesTightDefaultSuffix {
                suffix = String(format: "%02d", index)
            } else {
                suffix = index == 1 ? "" : String(format: " %02d", index)
            }
            let filename = "\(baseName)\(suffix).\(format.fileExtension)"
            let candidate = folder.appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    public func defaultBaseName(for date: Date = Date()) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%02d%02d%02d New Recording ", year % 100, month, day)
    }

    private func sanitizedBaseName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let illegal = CharacterSet(charactersIn: "/:")
        return trimmed
            .components(separatedBy: illegal)
            .joined(separator: "-")
    }
}
