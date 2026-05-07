import AppKit
import TaurusRecorderCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    @State private var draftSaveFolderURL = FileManager.default.homeDirectoryForCurrentUser
    @State private var draftOutputFormat: OutputFormat = .m4a
    @State private var draftInputMode: RecordingInputMode = .computer
    @State private var draftInputGain: InputGain = .unity
    @State private var selectedTab = SettingsTab.general

    private let permissionHelper = ScreenCapturePermissionHelper()

    private var hasChanges: Bool {
        draftSaveFolderURL != appSettings.defaultSaveFolderURL
            || draftOutputFormat != appSettings.defaultOutputFormat
            || draftInputMode != appSettings.defaultInputMode
            || draftInputGain != appSettings.defaultInputGain
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }
                .tag(SettingsTab.general)

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .padding(20)
        .frame(width: 620, height: 430)
        .onAppear {
            selectedTab = .general
            loadDraftFromSettings()
        }
    }

    private var generalTab: some View {
        VStack(spacing: 16) {
            Form {
                Section("Recording Defaults") {
                    FormatSelector(selection: $draftOutputFormat) {}
                    SourceSelector(selection: $draftInputMode)
                    GainSlider(gain: $draftInputGain)

                    HStack {
                        Text("Save Folder")
                        Text(draftSaveFolderURL.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose") {
                            chooseDraftSaveFolder()
                        }
                        Button("Open") {
                            NSWorkspace.shared.open(draftSaveFolderURL)
                        }
                    }
                }

            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    loadDraftFromSettings()
                    dismiss()
                }

                Button("Save") {
                    appSettings.updateDefaults(
                        saveFolderURL: draftSaveFolderURL,
                        outputFormat: draftOutputFormat,
                        inputMode: draftInputMode,
                        inputGain: draftInputGain
                    )
                    loadDraftFromSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
            }
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Taurus Recorder")
                    .font(.title2.weight(.semibold))
                Text("© \(String(Calendar.current.component(.year, from: Date()))) Jee Hoon Chung (정지훈)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(permissionHelper.onboardingMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions")
                    .font(.headline)
                Text("Computer audio capture uses macOS Screen Recording permission. Microphone capture uses macOS Microphone permission. Taurus Recorder does not save screen video.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Screen Recording Settings") {
                    permissionHelper.openScreenRecordingSettings()
                }
            }

            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func loadDraftFromSettings() {
        draftSaveFolderURL = appSettings.defaultSaveFolderURL
        draftOutputFormat = appSettings.defaultOutputFormat
        draftInputMode = appSettings.defaultInputMode
        draftInputGain = appSettings.defaultInputGain
    }

    private func chooseDraftSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = draftSaveFolderURL

        if panel.runModal() == .OK, let url = panel.url {
            draftSaveFolderURL = url
        }
    }

    private enum SettingsTab: Hashable {
        case general
        case about
    }
}
