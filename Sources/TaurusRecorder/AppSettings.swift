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

    @Published var defaultInputGain: InputGain {
        didSet {
            UserDefaults.standard.set(defaultInputGain.multiplier, forKey: Keys.defaultInputGain)
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
        if UserDefaults.standard.object(forKey: Keys.defaultInputGain) != nil {
            defaultInputGain = InputGain(multiplier: UserDefaults.standard.float(forKey: Keys.defaultInputGain))
        } else {
            defaultInputGain = .unity
        }

        UserDefaults.standard.set(defaultOutputFormat.rawValue, forKey: Keys.defaultOutputFormat)
    }

    func updateDefaults(
        saveFolderURL: URL,
        outputFormat: OutputFormat,
        inputGain: InputGain
    ) {
        defaultSaveFolderURL = saveFolderURL
        defaultOutputFormat = OutputFormat.availableDefault(preferred: outputFormat)
        defaultInputGain = inputGain
    }

    private enum Keys {
        static let defaultSaveFolderPath = "defaultSaveFolderPath"
        static let defaultOutputFormat = "defaultOutputFormat"
        static let defaultInputGain = "defaultInputGain"
        static let didApplyEmbeddedMP3DefaultMigration = "didApplyEmbeddedMP3DefaultMigration"
    }
}
