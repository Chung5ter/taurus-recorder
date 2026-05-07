import AppKit
import Foundation
import TaurusRecorderCore

@MainActor
final class AppSettings: ObservableObject {
    @Published var defaultSaveFolderURL: URL {
        didSet {
            UserDefaults.standard.set(defaultSaveFolderURL.path, forKey: Keys.defaultSaveFolderPath)
        }
    }

    @Published var defaultOutputFormat: OutputFormat {
        didSet {
            UserDefaults.standard.set(defaultOutputFormat.rawValue, forKey: Keys.defaultOutputFormat)
        }
    }

    init() {
        let fallbackFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser

        if let savedPath = UserDefaults.standard.string(forKey: Keys.defaultSaveFolderPath), !savedPath.isEmpty {
            defaultSaveFolderURL = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            defaultSaveFolderURL = fallbackFolder
        }

        if !UserDefaults.standard.bool(forKey: Keys.didApplyEmbeddedMP3DefaultMigration) {
            defaultOutputFormat = OutputFormat.availableDefault(preferred: .mp3)
            UserDefaults.standard.set(true, forKey: Keys.didApplyEmbeddedMP3DefaultMigration)
        } else {
            let rawFormat = UserDefaults.standard.string(forKey: Keys.defaultOutputFormat)
            defaultOutputFormat = OutputFormat.availableDefault(
                preferred: rawFormat.flatMap(OutputFormat.init(rawValue:))
            )
        }
        UserDefaults.standard.set(defaultOutputFormat.rawValue, forKey: Keys.defaultOutputFormat)
    }

    func updateDefaults(saveFolderURL: URL, outputFormat: OutputFormat) {
        defaultSaveFolderURL = saveFolderURL
        defaultOutputFormat = OutputFormat.availableDefault(preferred: outputFormat)
    }

    private enum Keys {
        static let defaultSaveFolderPath = "defaultSaveFolderPath"
        static let defaultOutputFormat = "defaultOutputFormat"
        static let didApplyEmbeddedMP3DefaultMigration = "didApplyEmbeddedMP3DefaultMigration"
    }
}
